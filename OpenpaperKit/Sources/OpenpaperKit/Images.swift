import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

public struct RenderedImage: @unchecked Sendable {
    public let cgImage: CGImage
    public var cost: Int { cgImage.bytesPerRow * cgImage.height }
}

public actor ImagePipeline {
    private struct Flight { let task: Task<RenderedImage, Error>; var users: Set<UUID> }
    private var flights: [String: Flight] = [:]
    private var cache: [String: RenderedImage] = [:]
    private var access: [String] = []
    private var cost = 0
    private let memoryLimit: Int
    private let diskLimit: Int
    private let directory: URL
    private let permits = PermitPool(limit: 4)
    private let session: URLSession

    public init(directory: URL) {
        self.directory = directory
        #if os(macOS)
        memoryLimit = 128 * 1024 * 1024; diskLimit = 1024 * 1024 * 1024
        #else
        memoryLimit = 64 * 1024 * 1024; diskLimit = 512 * 1024 * 1024
        #endif
        let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    public func image(url: URL, maxPixel: Int = 720) async throws -> RenderedImage {
        guard url.isFileURL || MediaURLs.isTrusted(url) else { throw OpenpaperError.invalidResponse }
        let pixels = min(4096, max(64, maxPixel))
        let key = SHA256.hash(data: Data("\(url.absoluteString)|\(pixels)".utf8)).map { String(format: "%02x", $0) }.joined()
        if let image = cache[key] { touch(key); return image }
        let user = UUID()
        let task: Task<RenderedImage, Error>
        if var flight = flights[key] { flight.users.insert(user); flights[key] = flight; task = flight.task }
        else {
            let permits = self.permits, session = self.session, directory = self.directory, limit = self.diskLimit
            task = Task.detached(priority: .userInitiated) {
                try await permits.acquire()
                do {
                    try Task.checkCancellation()
                    let image: RenderedImage
                    if url.isFileURL { image = try ImageProcessing.thumbnail(url: url, pixels: pixels) }
                    else {
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        let cached = directory.appendingPathComponent(key)
                        if FileManager.default.fileExists(atPath: cached.path), let decoded = try? ImageProcessing.thumbnail(url: cached, pixels: pixels) { image = decoded }
                        else {
                            let (data, response) = try await session.data(from: url)
                            try Task.checkCancellation()
                            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode), data.count <= 20_000_000 else { throw OpenpaperError.invalidResponse }
                            image = try ImageProcessing.thumbnail(data: data, pixels: pixels)
                            try data.write(to: cached, options: .atomic)
                            try Self.pruneDisk(directory: directory, limit: limit)
                        }
                        try? FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: cached.path)
                    }
                    await permits.release(); return image
                } catch { await permits.release(); throw error }
            }
            flights[key] = Flight(task: task, users: [user])
        }
        return try await withTaskCancellationHandler {
            do {
                let image = try await task.value
                try Task.checkCancellation()
                finish(key: key, user: user)
                if cache[key] == nil { cache[key] = image; cost += image.cost; touch(key); trim() }
                return image
            } catch { finish(key: key, user: user); throw error }
        } onCancel: { Task { await self.cancel(key: key, user: user) } }
    }
    private func finish(key: String, user: UUID) {
        guard var flight = flights[key] else { return }
        flight.users.remove(user)
        flights[key] = flight.users.isEmpty ? nil : flight
    }
    private func cancel(key: String, user: UUID) {
        guard var flight = flights[key] else { return }
        flight.users.remove(user)
        if flight.users.isEmpty { flight.task.cancel(); flights[key] = nil } else { flights[key] = flight }
    }
    private func touch(_ key: String) { access.removeAll { $0 == key }; access.append(key) }
    private func trim() {
        while cost > memoryLimit, let oldest = access.first {
            access.removeFirst(); if let removed = cache.removeValue(forKey: oldest) { cost -= removed.cost }
        }
    }
    public func clearMemory() { cache.removeAll(); access.removeAll(); cost = 0 }
    public func clearDisk() throws {
        // Cancel active writes before removing only thumbnail cache files.
        for flight in flights.values { flight.task.cancel() }
        flights.removeAll(); clearMemory()
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
    private static func pruneDisk(directory: URL, limit: Int) throws {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)).compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var total = files.reduce(0) { $0 + $1.1 }
        for (url, size, _) in files where total > limit { try FileManager.default.removeItem(at: url); total -= size }
    }
}

public enum ImageProcessing {
    public static func thumbnail(url: URL, pixels: Int) throws -> RenderedImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { throw OpenpaperError.invalidResponse }
        return try thumbnail(source: source, pixels: pixels)
    }
    public static func thumbnail(data: Data, pixels: Int) throws -> RenderedImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { throw OpenpaperError.invalidResponse }
        return try thumbnail(source: source, pixels: pixels)
    }
    private static func thumbnail(source: CGImageSource, pixels: Int) throws -> RenderedImage {
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: pixels, kCGImageSourceShouldCacheImmediately: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw OpenpaperError.invalidResponse }
        return RenderedImage(cgImage: image)
    }
    public static func validateOriginal(_ url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source), [UTType.jpeg.identifier, UTType.png.identifier].contains(type as String),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 50_000, height <= 50_000 else { throw OpenpaperError.invalidResponse }
    }
    public static func crop(original: URL, output: URL, aspect: Double, zoom: Double, offsetX: Double, offsetY: Double) throws -> URL {
        guard original.resolvingSymlinksInPath() != output.resolvingSymlinksInPath() else { throw OpenpaperError.validation("El encuadre debe guardarse en una copia distinta del original.") }
        try validateOriginal(original)
        guard let source = CGImageSourceCreateWithURL(original as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int else { throw OpenpaperError.invalidResponse }
        guard width * height <= 80_000_000 else { throw OpenpaperError.validation("Este original supera los 80 megapíxeles permitidos para encuadrar en memoria. Puedes exportar el original para editarlo.") }
        let image = try thumbnail(source: source, pixels: max(width, height)).cgImage
        let bounds = CropGeometry(imageWidth: Double(image.width), imageHeight: Double(image.height), aspect: aspect, zoom: zoom, offsetX: offsetX, offsetY: offsetY)
        guard let cropped = image.cropping(to: CGRect(x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height).integral),
              let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { throw OpenpaperError.invalidResponse }
        CGImageDestinationAddImage(destination, cropped, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw OpenpaperError.storage("No se pudo guardar la copia encuadrada.") }
        return output
    }
}
