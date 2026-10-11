import Foundation
import CryptoKit

/// Compressed sources are shared across display sizes and explicit downloads.
public actor MediaCache {
    typealias Transfer = @Sendable (URL, URL, URL, Int, @escaping @Sendable (Double) -> Void) async throws -> URL
    private struct Flight {
        var task: Task<URL, Error>
        var users: [UUID: @Sendable (Double) -> Void]
    }
    private var flights: [String: Flight] = [:]
    private var clearing = false
    private var pins: [String: Int] = [:]
    private let originals = PermitPool(limit: 2)
    private let thumbnails = PermitPool(limit: 4)
    let directory: URL
    private let limit: Int
    private let transfer: Transfer

    public init(directory: URL) {
        self.init(directory: directory, transfer: { source, target, resume, maxBytes, progress in
            try await DownloadOperation(source: source, destination: target, resumeFile: resume, maxBytes: maxBytes, progress: progress).run()
        })
    }
    init(directory: URL, transfer: @escaping Transfer) {
        self.directory = directory; self.transfer = transfer
        #if os(macOS)
        limit = 1024 * 1024 * 1024
        #else
        limit = 512 * 1024 * 1024
        #endif
    }
    private func key(_ url: URL) -> String { SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined() }

    func withFile<T: Sendable>(url: URL, original: Bool, previousResume: URL? = nil, progress: @escaping @Sendable (Double) -> Void = { _ in },
                              use: @escaping @Sendable (URL) async throws -> T) async throws -> T {
        guard MediaURLs.isTrusted(url) else { throw OpenpaperError.invalidResponse }
        try Task.checkCancellation()
        guard !clearing else { throw CancellationError() }
        let key = key(url), user = UUID(), file = directory.appendingPathComponent(key)
        pins[key, default: 0] += 1
        defer {
            let remaining = (pins[key] ?? 1) - 1
            pins[key] = remaining > 0 ? remaining : nil
        }
        let task: Task<URL, Error>
        if FileManager.default.fileExists(atPath: file.path) {
            task = Task { file }
        } else if var flight = flights[key] {
            flight.users[user] = progress; flights[key] = flight; task = flight.task
        } else {
            let pool = original ? originals : thumbnails, transfer = transfer, directory = directory, owner = self
            task = Task {
                try await pool.acquire()
                do {
                    try Task.checkCancellation()
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let resumes = directory.appendingPathComponent("Resumes", isDirectory: true)
                    try FileManager.default.createDirectory(at: resumes, withIntermediateDirectories: true)
                    let resume = resumes.appendingPathComponent(key + ".resume")
                    if let previousResume, !FileManager.default.fileExists(atPath: resume.path), FileManager.default.fileExists(atPath: previousResume.path) {
                        try FileManager.default.copyItem(at: previousResume, to: resume)
                    }
                    let result = try await transfer(url, file, resume, original ? 300_000_000 : 20_000_000) { value in
                        Task { await owner.report(key, value: value) }
                    }
                    try Task.checkCancellation()
                    await pool.release(); return result
                } catch { await pool.release(); throw error }
            }
            flights[key] = Flight(task: task, users: [user: progress])
        }
        return try await withTaskCancellationHandler {
            do {
                let file = try await task.value
                try Task.checkCancellation()
                try? FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: file.path)
                let result = try await use(file)
                finish(key, user: user)
                try prune()
                return result
            } catch { finish(key, user: user); throw error }
        } onCancel: { Task { await self.cancel(key, user: user) } }
    }
    private func report(_ key: String, value: Double) { for listener in flights[key]?.users.values ?? [:].values { listener(value) } }
    private func finish(_ key: String, user: UUID) {
        guard var flight = flights[key], flight.users.removeValue(forKey: user) != nil else { return }
        flights[key] = flight.users.isEmpty ? nil : flight
    }
    private func cancel(_ key: String, user: UUID) {
        guard var flight = flights[key], flight.users.removeValue(forKey: user) != nil else { return }
        if flight.users.isEmpty { flight.task.cancel(); flights[key] = nil } else { flights[key] = flight }
    }
    func activeConsumers(url: URL) -> Int { flights[key(url)]?.users.count ?? 0 }
    public func clear() async throws {
        clearing = true
        defer { clearing = false }
        let tasks = flights.values.map(\.task)
        tasks.forEach { $0.cancel() }
        for task in tasks { _ = try? await task.value }
        flights.removeAll()
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where (pins[file.lastPathComponent] ?? 0) == 0 {
            try FileManager.default.removeItem(at: file)
        }
    }
    private func prune() throws {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)).compactMap { file -> (URL, Int, Date)? in
            guard let v = try? file.resourceValues(forKeys: keys), v.isRegularFile == true else { return nil }
            return (file, v.fileSize ?? 0, v.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var bytes = files.reduce(0) { $0 + $1.1 }
        for (file, size, _) in files where bytes > limit && (pins[file.lastPathComponent] ?? 0) == 0 {
            try FileManager.default.removeItem(at: file); bytes -= size
        }
    }
}
