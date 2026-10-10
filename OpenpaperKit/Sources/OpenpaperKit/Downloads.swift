import Foundation

public actor DownloadService {
    private let root: URL
    private let permits = PermitPool(limit: 2)
    private var active: [String: (UUID, Task<URL, Error>)] = [:]
    public init(root: URL) { self.root = root }

    public func download(_ wallpaper: Wallpaper, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        guard wallpaper.provider == "wallhaven", WallhavenSearchOptions.validID(wallpaper.id), MediaURLs.isTrusted(wallpaper.path) else { throw OpenpaperError.invalidResponse }
        let name = "wallhaven-\(wallpaper.id).\(wallpaper.extensionName)"
        let destination = root.appendingPathComponent("Originals", isDirectory: true).appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: destination.path) { try ImageProcessing.validateOriginal(destination); return destination }
        if let running = active[wallpaper.identity.key] { return try await running.1.value }
        let identifier = UUID(), permits = self.permits, root = self.root
        let task = Task.detached(priority: .userInitiated) {
            try await permits.acquire()
            do {
                try Task.checkCancellation()
                let resumes = root.appendingPathComponent("Resumes", isDirectory: true)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: resumes, withIntermediateDirectories: true)
                let operation = DownloadOperation(source: wallpaper.path, destination: destination,
                                                  resumeFile: resumes.appendingPathComponent("\(wallpaper.id).resume"), progress: progress)
                let result = try await operation.run()
                await permits.release(); return result
            } catch { await permits.release(); throw error }
        }
        active[wallpaper.identity.key] = (identifier, task)
        do {
            let file = try await task.value
            if active[wallpaper.identity.key]?.0 == identifier { active[wallpaper.identity.key] = nil }
            return file
        } catch {
            if active[wallpaper.identity.key]?.0 == identifier { active[wallpaper.identity.key] = nil }
            throw error
        }
    }
    public func cancel(_ identity: WallpaperIdentity) { active[identity.key]?.1.cancel() }
}

private final class DownloadOperation: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let source: URL
    private let destination: URL
    private let resumeFile: URL
    private let progress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var task: URLSessionDownloadTask?
    private var session: URLSession?
    private var result: Result<URL, Error>?
    private var cancelled = false
    private var lastProgress = ContinuousClock.now

    init(source: URL, destination: URL, resumeFile: URL, progress: @escaping @Sendable (Double) -> Void) {
        self.source = source; self.destination = destination; self.resumeFile = resumeFile; self.progress = progress
    }
    func run() async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    if cancelled || Task.isCancelled { continuation.resume(throwing: CancellationError()); return }
                    self.continuation = continuation
                    let config = URLSessionConfiguration.ephemeral
                    config.timeoutIntervalForRequest = 60; config.timeoutIntervalForResource = 1800
                    let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
                    self.session = session
                    if let resume = try? Data(contentsOf: resumeFile) { task = session.downloadTask(withResumeData: resume) }
                    else { task = session.downloadTask(with: source) }
                    task?.resume()
                }
            }
        } onCancel: {
            let task = self.lock.withLock { self.cancelled = true; return self.task }
            task?.cancel()
        }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > 300_000_000 || totalBytesExpectedToWrite > 300_000_000 {
            lock.withLock { result = .failure(OpenpaperError.storage("El original supera el límite de 300 MB.")) }
            downloadTask.cancel(); return
        }
        let now = ContinuousClock.now
        if lastProgress.duration(to: now) >= .milliseconds(100) || totalBytesWritten == totalBytesExpectedToWrite {
            lastProgress = now
            progress(totalBytesExpectedToWrite > 0 ? min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) : 0)
        }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard let response = downloadTask.response as? HTTPURLResponse else { throw OpenpaperError.invalidResponse }
            guard (200..<300).contains(response.statusCode) else { throw OpenpaperError.http(response.statusCode) }
            try ImageProcessing.validateOriginal(location)
            // A validated temporary image is moved atomically; the existing original is never replaced.
            if !FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.moveItem(at: location, to: destination) }
            try? FileManager.default.removeItem(at: resumeFile)
            lock.withLock { result = .success(destination) }
        } catch { lock.withLock { result = .failure(error) } }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let data = (error as NSError?)?.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            try? data.write(to: resumeFile, options: .atomic)
        } else if error != nil { try? FileManager.default.removeItem(at: resumeFile) }
        let outcome = lock.withLock { () -> (CheckedContinuation<URL, Error>?, Result<URL, Error>) in
            let continuation = self.continuation; self.continuation = nil
            return (continuation, result ?? .failure(error ?? OpenpaperError.invalidResponse))
        }
        outcome.0?.resume(with: outcome.1)
        session.finishTasksAndInvalidate()
        lock.withLock { self.session = nil; self.task = nil }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.url.map(MediaURLs.isTrusted) == true ? request : nil)
    }
}
