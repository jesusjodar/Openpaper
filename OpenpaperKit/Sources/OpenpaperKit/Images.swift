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
    private let media: MediaCache
    private let permits = PermitPool(limit: 4)

    public init(directory: URL, media: MediaCache? = nil) {
        self.media = media ?? MediaCache(directory: directory)
        #if os(macOS)
        memoryLimit = 128 * 1024 * 1024
        #else
        memoryLimit = 64 * 1024 * 1024
        #endif
    }

    public func image(url: URL, maxPixel: Int, original: Bool = false) async throws -> RenderedImage {
        guard url.isFileURL || MediaURLs.isTrusted(url) else { throw OpenpaperError.invalidResponse }
        let pixels = max(1, min(50_000, maxPixel))
        let key = SHA256.hash(data: Data("\(url.absoluteString)|\(pixels)".utf8)).map { String(format: "%02x", $0) }.joined()
        if let image = cache[key] { touch(key); return image }
        let user = UUID()
        let task: Task<RenderedImage, Error>
        if var flight = flights[key] { flight.users.insert(user); flights[key] = flight; task = flight.task }
        else {
            let permits = self.permits, media = self.media
            task = Task.detached(priority: .userInitiated) {
                let render: @Sendable (URL) async throws -> RenderedImage = { file in
                    try await permits.acquire()
                    do {
                        try Task.checkCancellation()
                        let image = try ImageProcessing.thumbnail(url: file, pixels: pixels)
                        await permits.release(); return image
                    } catch { await permits.release(); throw error }
                }
                if url.isFileURL { return try await render(url) }
                return try await media.withFile(url: url, original: original, use: render)
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
    public func clearDisk() async throws {
        for flight in flights.values { flight.task.cancel() }
        flights.removeAll(); clearMemory()
        try await media.clear()
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
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? pixels
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? pixels
        let target = min(max(width, height), max(1, pixels))
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: target, kCGImageSourceShouldCacheImmediately: true]
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
