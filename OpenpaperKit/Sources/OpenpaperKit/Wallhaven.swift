import Foundation

public actor PermitPool {
    private var available: Int
    private var waiters: [(UUID, CheckedContinuation<Void, Error>)] = []
    public init(limit: Int) { precondition(limit > 0); available = limit }
    public func acquire() async throws {
        try Task.checkCancellation()
        if available > 0 { available -= 1; return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else { waiters.append((id, continuation)) }
            }
        } onCancel: { Task { await self.cancel(id) } }
    }
    private func cancel(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.0 == id }) else { return }
        waiters.remove(at: index).1.resume(throwing: CancellationError())
    }
    public func release() {
        if waiters.isEmpty { available += 1 }
        else { waiters.removeFirst().1.resume() }
    }
}

public actor APIPacer {
    private var next = ContinuousClock.now
    private let spacing: Duration
    public init(spacing: Duration = .milliseconds(1500)) { self.spacing = spacing }
    public func wait() async throws {
        let slot = max(next, .now)
        next = slot + spacing
        try await ContinuousClock().sleep(until: slot)
        try Task.checkCancellation()
    }
    public func deferRequests(seconds: Int) { next = max(next, .now + .seconds(seconds)) }
}

private final class APIRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard let url = request.url, url.scheme == "https", ["wallhaven.cc", "www.whvn.cc"].contains(url.host ?? "") else {
            completionHandler(nil); return
        }
        completionHandler(request)
    }
}

public actor WallhavenClient: WallpaperProvider {
    public nonisolated let capabilities = ProviderCapabilities.wallhaven
    private let session: URLSession
    private let pacer: APIPacer
    private var apiKey: String?
    private var policy = ContentPolicy()

    public init(session: URLSession? = nil, pacer: APIPacer = APIPacer()) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 90
        self.session = session ?? URLSession(configuration: config, delegate: APIRedirectDelegate(), delegateQueue: nil)
        self.pacer = pacer
    }

    public func configure(key: String?, policy: ContentPolicy) { apiKey = key; self.policy = policy }

    public func search(_ options: WallhavenSearchOptions, page: Int = 1, seed: String? = nil) async throws -> SearchPage {
        try options.validate(policy: policy, hasKey: apiKey != nil)
        guard page > 0 else { throw OpenpaperError.validation("La página debe ser positiva.") }
        if let seed, !seed.isEmpty {
            guard seed.count == 6 && seed.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }) else { throw OpenpaperError.invalidResponse }
        }
        let result: ListingResponse = try await get("search", query: options.queryItems(page: page, seed: seed))
        return try result.page(policy: policy)
    }

    public func detail(id: String) async throws -> Wallpaper {
        guard WallhavenSearchOptions.validID(id) else { throw OpenpaperError.validation("El ID debe tener seis letras minúsculas o cifras.") }
        let result: Envelope<WallpaperDTO> = try await get("w/\(id)")
        let wallpaper = try result.data.wallpaper()
        guard policy.permits(wallpaper) else { throw OpenpaperError.validation("Este fondo no cumple el contenido permitido en Ajustes.") }
        return wallpaper
    }

    public func tag(id: Int) async throws -> WallpaperTag {
        guard id > 0 else { throw OpenpaperError.validation("La etiqueta no es válida.") }
        let result: Envelope<WallpaperTag> = try await get("tag/\(id)")
        return result.data
    }

    public func settings() async throws -> AccountPreferences {
        guard apiKey != nil else { throw OpenpaperError.unauthorized }
        let result: Envelope<AccountPreferences> = try await get("settings")
        return result.data
    }

    public func collections(username: String? = nil) async throws -> [RemoteCollection] {
        if let username { try validateUsername(username) }
        else if apiKey == nil { throw OpenpaperError.unauthorized }
        let result: Envelope<[RemoteCollection]> = try await get("collections" + (username.map { "/\($0)" } ?? ""))
        return result.data
    }

    public func collection(username: String, id: Int, page: Int = 1) async throws -> SearchPage {
        try validateUsername(username)
        guard id > 0, page > 0 else { throw OpenpaperError.validation("La colección o la página no es válida.") }
        let purity = "1\(policy.sketchy ? 1 : 0)\(policy.nsfw && apiKey != nil ? 1 : 0)"
        let result: ListingResponse = try await get("collections/\(username)/\(id)", query: [URLQueryItem(name: "purity", value: purity), URLQueryItem(name: "page", value: String(page))])
        return try result.page(policy: policy)
    }

    private func validateUsername(_ value: String) throws {
        guard !value.isEmpty, value.count <= 64, value.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-" )).contains($0) }) else {
            throw OpenpaperError.validation("El nombre de usuario admite letras, cifras, guion y guion bajo.")
        }
    }

    private func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await pacer.wait()
        var components = URLComponents(string: "https://wallhaven.cc/api/v1/\(path)")!
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Openpaper/0.1 (https://github.com/jesusjodar/Openpaper)", forHTTPHeaderField: "User-Agent")
        if let apiKey { request.setValue(apiKey, forHTTPHeaderField: "X-API-Key") }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw OpenpaperError.invalidResponse }
        if response.statusCode == 401 { throw OpenpaperError.unauthorized }
        if response.statusCode == 429 {
            let delay = min(3600, max(1, Int(response.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60))
            await pacer.deferRequests(seconds: delay)
            throw OpenpaperError.rateLimited(delay)
        }
        guard (200..<300).contains(response.statusCode) else { throw OpenpaperError.http(response.statusCode) }
        guard data.count <= 10_000_000 else { throw OpenpaperError.invalidResponse }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw OpenpaperError.invalidResponse }
    }

    public static func decodeListing(_ data: Data, policy: ContentPolicy = .init()) throws -> SearchPage {
        try JSONDecoder().decode(ListingResponse.self, from: data).page(policy: policy)
    }
}

private struct Envelope<T: Decodable & Sendable>: Decodable, Sendable { let data: T }

private struct ListingResponse: Decodable, Sendable {
    let data: [WallpaperDTO]
    let meta: Meta
    struct Meta: Decodable, Sendable {
        let current_page: Int
        let last_page: Int
        let total: Int
        let seed: String?
    }
    func page(policy: ContentPolicy) throws -> SearchPage {
        guard meta.current_page > 0, meta.last_page >= 0, meta.total >= 0 else { throw OpenpaperError.invalidResponse }
        return SearchPage(wallpapers: try data.map { try $0.wallpaper() }.filter { policy.permits($0) },
                          currentPage: meta.current_page, lastPage: meta.last_page, total: meta.total, seed: meta.seed)
    }
}

private struct WallpaperDTO: Decodable, Sendable {
    let id: String
    let url: URL
    let path: URL
    let thumbs: Thumbs
    let dimension_x: Int?
    let dimension_y: Int?
    let file_size: Int?
    let file_type: String?
    let purity: String?
    let category: String?
    let colors: [String]?
    let tags: [WallpaperTag]?
    let uploader: Uploader?
    let source: String?
    let views: Int?
    let favorites: Int?
    struct Thumbs: Decodable, Sendable { let large: URL?; let original: URL?; let small: URL? }
    struct Uploader: Decodable, Sendable { let username: String }
    func wallpaper() throws -> Wallpaper {
        guard WallhavenSearchOptions.validID(id), let thumb = thumbs.large ?? thumbs.original ?? thumbs.small,
              MediaURLs.isTrusted(path), MediaURLs.isTrusted(thumb), url.scheme == "https",
              ["wallhaven.cc", "www.whvn.cc"].contains(url.host ?? "") else { throw OpenpaperError.invalidResponse }
        return Wallpaper(id: id, url: url, path: path, thumbnail: thumb, width: dimension_x ?? 0,
                         height: dimension_y ?? 0, fileSize: file_size ?? 0, fileType: file_type ?? "image/jpeg",
                         purity: purity ?? "unknown", category: category ?? "", colors: colors ?? [], tags: tags ?? [],
                         uploader: uploader?.username, source: source, views: views ?? 0, favorites: favorites ?? 0)
    }
}

enum MediaURLs {
    static func isTrusted(_ url: URL) -> Bool {
        url.scheme == "https" && ["w.wallhaven.cc", "th.wallhaven.cc", "w.whvn.cc", "th.whvn.cc"].contains(url.host ?? "") && url.user == nil && url.password == nil && (url.port == nil || url.port == 443) && url.query == nil
    }
}
