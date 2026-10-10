import Foundation
import Observation
import Network

public enum Destination: String, CaseIterable, Identifiable {
    case explore = "Explorar", search = "Buscar", library = "Biblioteca"
    public var id: String { rawValue }
    public var symbol: String { switch self { case .explore: "safari"; case .search: "magnifyingglass"; case .library: "photo.stack" } }
}

@MainActor @Observable public final class SearchFeed {
    public var options = WallhavenSearchOptions()
    public private(set) var results: [Wallpaper] = []
    public private(set) var loading = false
    public private(set) var error: String?
    public private(set) var total = 0
    public private(set) var currentPage = 0
    public private(set) var lastPage = 0
    public private(set) var seed: String?
    public var remote: (username: String, id: Int)?
    private var generation = UUID()
    private var task: Task<Void, Never>?
    private var prefetched: SearchPage?
    private var prefetchTask: Task<Void, Never>?
    private var requestedOptions: WallhavenSearchOptions?
    public var needsRefresh: Bool { requestedOptions != options }
    public init() {}
    public func refresh(client: WallhavenClient, prefetch: Bool = false) async {
        task?.cancel(); prefetchTask?.cancel(); prefetched = nil
        generation = UUID(); let token = generation
        loading = true; error = nil; currentPage = 0; lastPage = 0; seed = nil; results = []
        let options = self.options, remote = self.remote
        requestedOptions = options
        let work = Task {
            do {
                let page = try await self.fetch(client: client, options: options, remote: remote, page: 1, seed: nil)
                guard !Task.isCancelled, generation == token else { return }
                accept(page, replace: true); loading = false
                if prefetch { prefetchNext(client: client) }
            } catch {
                guard !Task.isCancelled, generation == token else { return }
                loading = false; self.error = error.localizedDescription
            }
        }
        task = work
        await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        if generation == token, work.isCancelled { loading = false }
    }
    public func next(client: WallhavenClient, prefetch: Bool = false) async {
        guard !loading, currentPage < lastPage else { return }
        let token = generation, number = currentPage + 1
        loading = true; error = nil
        defer { if token == generation { loading = false } }
        do {
            let page: SearchPage
            if let cached = prefetched, cached.currentPage == number { page = cached; prefetched = nil }
            else { prefetchTask?.cancel(); page = try await fetch(client: client, options: options, remote: remote, page: number, seed: seed) }
            guard token == generation, !Task.isCancelled else { return }
            accept(page, replace: false); loading = false
            if prefetch { prefetchNext(client: client) }
        } catch {
            guard token == generation else { return }
            loading = false
            if !(error is CancellationError) { self.error = error.localizedDescription }
        }
    }
    private func fetch(client: WallhavenClient, options: WallhavenSearchOptions, remote: (username: String, id: Int)?, page: Int, seed: String?) async throws -> SearchPage {
        if let remote { return try await client.collection(username: remote.username, id: remote.id, page: page) }
        return try await client.search(options, page: page, seed: seed)
    }
    private func accept(_ page: SearchPage, replace: Bool) {
        if replace { results = page.wallpapers }
        else { let existing = Set(results.map(\.identity)); results += page.wallpapers.filter { !existing.contains($0.identity) } }
        currentPage = page.currentPage; lastPage = page.lastPage; total = page.total
        // Wallhaven can echo a different seed on later pages; preserve the initial search seed.
        if replace { seed = page.seed }
    }
    private func prefetchNext(client: WallhavenClient) {
        guard currentPage < lastPage, remote == nil else { return }
        let options = self.options, number = currentPage + 1, seed = self.seed, token = generation
        prefetchTask = Task {
            do {
                let page = try await client.search(options, page: number, seed: seed)
                if !Task.isCancelled, token == generation { prefetched = page }
            } catch { /* Prefetch failure is retried by the visible pagination action. */ }
        }
    }
    public func clear() {
        task?.cancel(); prefetchTask?.cancel(); generation = UUID(); prefetched = nil
        results = []; loading = false; currentPage = 0; lastPage = 0; error = nil
        requestedOptions = nil
    }
}

struct AppPreferences: Codable {
    var policy = ContentPolicy()
    var defaultOptions = WallhavenSearchOptions()
    var history: [String] = []
    var rotationEnabled = false
    var rotationPaused = false
    var rotationInterval = 3600
    var rotationRandom = true
    var rotationSource = ""
    var rotationTarget = ""
}

@MainActor @Observable public final class AppSession {
    public var destination: Destination = .explore
    public private(set) var library: LibraryStore?
    private let apiPacer: APIPacer
    public let client: WallhavenClient
    public let explore = SearchFeed()
    public let search = SearchFeed()
    public private(set) var images: ImagePipeline?
    public private(set) var downloads: DownloadService?
    public private(set) var startupError: String?
    public var message: String?
    public var notice: String?
    public private(set) var keyValidated = false
    public private(set) var hasKey = false
    public private(set) var jobs: [String: Double] = [:]
    public private(set) var downloadErrors: [String: String] = [:]
    public private(set) var constrainedNetwork = true
    private(set) var preferences: AppPreferences
    public var busy = false
    private let defaults: UserDefaults
    private let monitor = NWPathMonitor()
    private var rotationTask: Task<Void, Never>?
    private var nextRotation = Date.now
    private var order = RotationOrder()
    private var rotating = false
    private var rotationCandidates: [Wallpaper] = []
    private var rotationPage = 0
    private var rotationLastPage = 0
    private var rotationSeed: String?
    private var rotationSeen: Set<String> = []
    private var started = false
    private var servicePreparation: Task<Void, Error>?
    #if os(macOS)
    public let application = MacWallpaperService()
    #endif

    public init(defaults: UserDefaults = .standard) {
        let pacer = APIPacer(); apiPacer = pacer; client = WallhavenClient(pacer: pacer)
        self.defaults = defaults
        preferences = defaults.data(forKey: "preferences-v1").flatMap { try? JSONDecoder().decode(AppPreferences.self, from: $0) } ?? .init()
        do {
            let store = try LibraryStore(); library = store
            downloads = DownloadService(root: store.root)
            let caches = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            images = ImagePipeline(directory: caches.appendingPathComponent("Openpaper/Thumbnails", isDirectory: true))
        } catch { startupError = error.localizedDescription }
        explore.options = preferences.defaultOptions; search.options = preferences.defaultOptions
        monitor.pathUpdateHandler = { [weak self] path in
            let restricted = path.isConstrained || path.isExpensive || path.status != .satisfied
            Task { @MainActor in self?.constrainedNetwork = restricted }
        }
        monitor.start(queue: DispatchQueue(label: "Openpaper.network"))
    }
    public var policy: ContentPolicy { .init(sketchy: preferences.policy.sketchy, nsfw: preferences.policy.nsfw && keyValidated) }
    public var allowPrefetch: Bool { !constrainedNetwork && !ProcessInfo.processInfo.isLowPowerModeEnabled }
    public var history: [String] { preferences.history }
    public var rotationEnabled: Bool { preferences.rotationEnabled }
    public var rotationPaused: Bool { preferences.rotationPaused }
    public var rotationInterval: Int { preferences.rotationInterval }
    public var rotationRandom: Bool { preferences.rotationRandom }
    public var rotationSource: String { preferences.rotationSource }
    public var rotationTarget: String { preferences.rotationTarget }
    public var rotationDescription: String {
        !rotationEnabled ? "Rotación desactivada" : rotationPaused ? "Rotación en pausa" : "Rotación activa · cada \(rotationInterval / 60) min"
    }
    private func savePreferences() {
        do { defaults.set(try JSONEncoder().encode(preferences), forKey: "preferences-v1") }
        catch { message = error.localizedDescription }
    }
    public func start() async {
        guard !started else { return }; started = true
        do { try await prepareServices() } catch { message = error.localizedDescription }
        startRotationLoop()
        await explore.refresh(client: client, prefetch: allowPrefetch)
    }
    public func prepareServices() async throws {
        if let servicePreparation { try await servicePreparation.value; return }
        let preparation = Task { @MainActor in
            let key = try KeychainStore.read(); hasKey = key != nil
            await client.configure(key: key, policy: .init(sketchy: preferences.policy.sketchy))
            if key != nil { _ = try await client.settings(); keyValidated = true }
            await client.configure(key: key, policy: policy)
        }
        servicePreparation = preparation
        do { try await preparation.value }
        catch { servicePreparation = nil; throw error }
    }
    public func connect(key: String) async {
        busy = true; defer { busy = false }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 200, !trimmed.contains(where: \.isWhitespace) else { message = "Introduce una clave API válida."; return }
        let validator = WallhavenClient(pacer: apiPacer)
        await validator.configure(key: trimmed, policy: .init())
        do {
            _ = try await validator.settings()
            try KeychainStore.write(trimmed); keyValidated = true; hasKey = true
            await client.configure(key: trimmed, policy: policy)
            notice = "Clave validada y guardada en el Llavero."
        } catch { message = error.localizedDescription }
    }
    public func disconnect() async {
        do {
            try KeychainStore.write(nil); keyValidated = false; hasKey = false
            preferences.policy.nsfw = false; savePreferences()
            await client.configure(key: nil, policy: policy); explore.clear(); search.clear()
            notice = "Clave eliminada del Llavero."
        } catch { message = error.localizedDescription }
    }
    public func setPolicy(sketchy: Bool, nsfw: Bool) async {
        guard !nsfw || keyValidated else { message = "Valida primero una clave API para activar NSFW."; return }
        preferences.policy = .init(sketchy: sketchy, nsfw: nsfw); savePreferences()
        do { await client.configure(key: try KeychainStore.read(), policy: policy) }
        catch { message = error.localizedDescription }
        explore.clear(); search.clear()
    }
    public func importAccountPreferences() async {
        do {
            let account = try await client.settings()
            var options = WallhavenSearchOptions()
            if let categories = account.categories {
                options.general = categories.contains("general"); options.anime = categories.contains("anime"); options.people = categories.contains("people")
            }
            options.resolutions = account.resolutions?.joined(separator: ",") ?? ""
            options.ratios = account.aspect_ratios?.joined(separator: ",") ?? ""
            options.topRange = account.toplist_range ?? "1M"
            let excludedTags = (account.tag_blacklist ?? []).filter { !$0.isEmpty }.map { "-\($0)" }
            if !excludedTags.isEmpty || !(account.user_blacklist ?? []).filter({ !$0.isEmpty }).isEmpty {
                notice = "Filtros importados con SFW. Las listas de bloqueo siguen aplicándose en Wallhaven; no se han convertido en una consulta distinta."
            } else { notice = "Filtros importados. El contenido permitido permanece en SFW hasta que lo actives explícitamente." }
            try options.validate(policy: policy, hasKey: keyValidated)
            preferences.defaultOptions = options; savePreferences(); explore.options = options; search.options = options
            await explore.refresh(client: client, prefetch: allowPrefetch)
        } catch { message = error.localizedDescription }
    }
    public func recordSearch() {
        let q = search.options.query
        guard !q.isEmpty else { return }
        preferences.history.removeAll { $0 == q }; preferences.history.insert(q, at: 0)
        preferences.history = Array(preferences.history.prefix(20)); savePreferences()
    }
    public func searchFor(_ query: String) {
        search.remote = nil; search.options.query = query; destination = .search
    }
    public func useSearch(_ options: WallhavenSearchOptions) {
        search.remote = nil; search.options = options; destination = .search
    }
    public func perform(_ action: () throws -> Void) {
        do { try action() } catch { message = error.localizedDescription }
    }
    @discardableResult public func download(_ wallpaper: Wallpaper) async throws -> URL {
        guard policy.permits(wallpaper) else { throw OpenpaperError.validation("Este fondo no cumple el contenido permitido.") }
        guard let library, let downloads else { throw OpenpaperError.storage("La biblioteca no está disponible.") }
        if let existing = library.localURL(wallpaper) { return existing }
        jobs[wallpaper.identity.key] = 0; downloadErrors[wallpaper.identity.key] = nil
        do {
            let file = try await downloads.download(wallpaper) { [weak self] progress in
                Task { @MainActor in
                    if self?.jobs[wallpaper.identity.key] != nil { self?.jobs[wallpaper.identity.key] = progress }
                }
            }
            try library.markDownloaded(wallpaper, fileName: file.lastPathComponent)
            jobs[wallpaper.identity.key] = nil
            guard policy.permits(wallpaper) else { throw OpenpaperError.validation("El contenido permitido cambió durante la descarga. La imagen se conserva en la biblioteca y permanece oculta.") }
            return file
        } catch {
            jobs[wallpaper.identity.key] = nil
            if !(error is CancellationError), (error as NSError).code != NSURLErrorCancelled { downloadErrors[wallpaper.identity.key] = error.localizedDescription }
            throw error
        }
    }
    public func cancelDownload(_ wallpaper: Wallpaper) { Task { await downloads?.cancel(wallpaper.identity) } }
    public func configureRotation(enabled: Bool? = nil, interval: Int? = nil, random: Bool? = nil, source: String? = nil, target: String? = nil) {
        if let enabled { preferences.rotationEnabled = enabled }
        if let interval, [900, 3600, 21600, 86400].contains(interval) { preferences.rotationInterval = interval }
        if let random { preferences.rotationRandom = random; resetRotationSource() }
        if let source { preferences.rotationSource = source; resetRotationSource() }
        if let target { preferences.rotationTarget = target }
        nextRotation = .now.addingTimeInterval(Double(rotationInterval)); savePreferences(); startRotationLoop()
    }
    public func toggleRotation() { preferences.rotationPaused.toggle(); nextRotation = .now.addingTimeInterval(Double(rotationInterval)); savePreferences() }
    private func resetRotationSource() {
        order = .init(); rotationCandidates = []; rotationPage = 0; rotationLastPage = 0; rotationSeed = nil; rotationSeen = []
    }
    private func startRotationLoop() {
        #if os(macOS)
        guard rotationTask == nil else { return }
        nextRotation = .now.addingTimeInterval(Double(rotationInterval))
        rotationTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                guard let self else { return }
                if rotationEnabled && !rotationPaused && Date.now >= nextRotation {
                    nextRotation = .now.addingTimeInterval(Double(rotationInterval))
                    await rotateNow()
                }
            }
        }
        #endif
    }
    public func rotateNow() async {
        #if os(macOS)
        guard !rotating, let library else { return }
        rotating = true; defer { rotating = false }
        do {
            var candidates: [Wallpaper] = []
            var fromSearchPage = false
            if rotationSource.hasPrefix("search:"), let id = UUID(uuidString: String(rotationSource.dropFirst(7))), let saved = library.searches.first(where: { $0.id == id }), var options = saved.options {
                do {
                    if constrainedNetwork { throw URLError(.notConnectedToInternet) }
                    if rotationPage > 0 && rotationPage >= rotationLastPage && rotationCandidates.isEmpty { resetRotationSource() }
                    if rotationRandom { options.sorting = .random }
                    var attempts = 0
                    while rotationCandidates.isEmpty && attempts < 3 {
                        let page = try await client.search(options, page: rotationPage + 1, seed: rotationSeed)
                        rotationPage = page.currentPage; rotationLastPage = page.lastPage
                        if rotationSeed == nil { rotationSeed = page.seed }
                        rotationCandidates = page.wallpapers.filter { !rotationSeen.contains($0.identity.key) && policy.permits($0) }
                        try library.cache(page.wallpapers, for: saved)
                        attempts += 1
                        if rotationPage >= rotationLastPage { break }
                    }
                    candidates = rotationCandidates; fromSearchPage = true
                }
                catch {
                    let resumeCandidates = library.items.filter { saved.cachedKeys.contains($0.key) }.compactMap(\.wallpaper).filter { policy.permits($0) && library.localURL($0) != nil }
                    candidates = resumeCandidates
                    if candidates.isEmpty { throw error }
                }
            } else if let id = UUID(uuidString: rotationSource), let collection = library.collections.first(where: { $0.id == id }) {
                candidates = library.items.filter { collection.keys.contains($0.key) }.compactMap(\.wallpaper)
            }
            candidates = candidates.filter { policy.permits($0) }
            if constrainedNetwork { candidates = candidates.filter { library.localURL($0) != nil } }
            let key = fromSearchPage ? candidates.first?.identity.key : order.next(ids: candidates.map { $0.identity.key }, random: rotationRandom)
            guard let key, let wallpaper = candidates.first(where: { $0.identity.key == key }) else {
                throw OpenpaperError.validation("La fuente de rotación no tiene fondos disponibles. El fondo actual se conserva.")
            }
            let file = try await download(wallpaper)
            try application.apply(file: file, target: rotationTarget.isEmpty ? nil : rotationTarget, fill: true)
            if fromSearchPage { rotationSeen.insert(key); rotationCandidates.removeAll { $0.identity.key == key } }
            nextRotation = .now.addingTimeInterval(Double(rotationInterval))
            notice = "Fondo cambiado: \(wallpaper.id)."
        } catch { message = error.localizedDescription }
        #endif
    }
}
