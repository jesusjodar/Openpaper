import Testing
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import OpenpaperKit

private func wallpaper(_ id: String = "abc123", purity: String = "sfw") -> Wallpaper {
    Wallpaper(id: id, url: URL(string: "https://wallhaven.cc/w/\(id)")!,
              path: URL(string: "https://w.wallhaven.cc/full/ab/wallhaven-\(id).jpg")!,
              thumbnail: URL(string: "https://th.wallhaven.cc/lg/ab/\(id).jpg")!,
              width: 1920, height: 1080, purity: purity)
}

private func fixture(id: String = "abc123", page: Int = 1, last: Int = 2, purity: String = "sfw", seed: String = "Ab1234") -> Data {
    Data("""
    {"data":[{"id":"\(id)","url":"https://wallhaven.cc/w/\(id)","path":"https://w.wallhaven.cc/full/ab/wallhaven-\(id).jpg","thumbs":{"large":"https://th.wallhaven.cc/lg/ab/\(id).jpg"},"purity":"\(purity)"}],"meta":{"current_page":\(page),"last_page":\(last),"total":48,"query":{"id":1,"tag":"test"},"seed":"\(seed)"}}
    """.utf8)
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable { var status = 200; var data = fixture(); var delay: Duration = .zero; var headers: [String: String] = [:] }
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var handler: @Sendable (URLRequest) -> Reply = { _ in Reply() }
        func set(_ handler: @escaping @Sendable (URLRequest) -> Reply) { lock.withLock { self.handler = handler } }
        func reply(_ request: URLRequest) -> Reply { lock.withLock { handler(request) } }
    }
    private static let state = State()
    private var work: Task<Void, Never>?
    static func handler(_ value: @escaping @Sendable (URLRequest) -> Reply) { state.set(value) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let reply = Self.state.reply(request)
        work = Task {
            do { try await Task.sleep(for: reply.delay); try Task.checkCancellation() } catch { return }
            guard let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers) else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: reply.data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { work?.cancel() }
    static func client() -> WallhavenClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockURLProtocol.self]
        return WallhavenClient(session: URLSession(configuration: config), pacer: APIPacer(spacing: .zero))
    }
}

@Suite(.serialized) struct OpenpaperTests {
    @Test func allFiltersTranslateWithoutChangingQuery() throws {
        var o = WallhavenSearchOptions()
        o.query = "+mountain -city @user type:png like:abc123"; o.general = false; o.sketchy = true; o.nsfw = true
        o.sorting = .toplist; o.ascending = true; o.topRange = "6M"; o.resolutions = "1920x1080,2560x1440"; o.ratios = "16x9,16x10"; o.color = "424153"
        try o.validate(policy: .init(sketchy: true, nsfw: true), hasKey: true)
        let values = Dictionary(uniqueKeysWithValues: o.queryItems(page: 3, seed: nil).map { ($0.name, $0.value!) })
        #expect(values["q"] == o.query); #expect(values["categories"] == "011"); #expect(values["purity"] == "111")
        #expect(values["sorting"] == "toplist"); #expect(values["order"] == "asc"); #expect(values["topRange"] == "6M")
        #expect(values["resolutions"] == o.resolutions); #expect(values["ratios"] == o.ratios); #expect(values["colors"] == o.color); #expect(values["page"] == "3")
        for sorting in SearchSorting.allCases { o.sorting = sorting; #expect(o.queryItems(page: 1, seed: "Ab1234").contains { $0.name == "sorting" && $0.value == sorting.rawValue }) }
        o.sorting = .random
        #expect(o.queryItems(page: 2, seed: "Ab1234").contains { $0.name == "seed" && $0.value == "Ab1234" })
        o.resolutions = ""; o.minimumResolution = "3840x2160"
        #expect(o.queryItems(page: 1, seed: nil).contains { $0.name == "atleast" && $0.value == "3840x2160" })
    }
    @Test(arguments: ["id:1 other", "id:0", "type:gif", "like:../../", "id:1 type:png"]) func invalidQueries(_ query: String) {
        var o = WallhavenSearchOptions(); o.query = query
        #expect(throws: OpenpaperError.self) { try o.validate(policy: .init(), hasKey: false) }
    }
    @Test func invalidFiltersAndExplicitContent() throws {
        var o = WallhavenSearchOptions(); o.nsfw = true
        #expect(throws: OpenpaperError.self) { try o.validate(policy: .init(nsfw: true), hasKey: false) }
        #expect(throws: OpenpaperError.self) { try o.validate(policy: .init(), hasKey: true) }
        o.nsfw = false; o.sketchy = true
        #expect(throws: OpenpaperError.self) { try o.validate(policy: .init(), hasKey: true) }
        o.sketchy = false; o.minimumResolution = "1920x1080"; o.resolutions = "1920x1080"
        #expect(throws: OpenpaperError.self) { try o.validate(policy: .init(), hasKey: false) }
        o.resolutions = ""; o.minimumResolution = "0x1080"
        #expect(throws: OpenpaperError.self) { try o.validate(policy: .init(), hasKey: false) }
        o.minimumResolution = ""; o.general = false; o.anime = false; o.people = false
        #expect(throws: OpenpaperError.self) { try o.validate(policy: .init(), hasKey: false) }
    }
    @Test func incompleteResponseAndRandomPagination() throws {
        let page = try WallhavenClient.decodeListing(fixture())
        #expect(page.currentPage == 1); #expect(page.lastPage == 2); #expect(page.seed == "Ab1234")
        #expect(page.wallpapers.first?.tags == []); #expect(page.wallpapers.first?.width == 0)
        #expect(try WallhavenClient.decodeListing(fixture(purity: "nsfw")).wallpapers.isEmpty)
        #expect(throws: (any Error).self) { try WallhavenClient.decodeListing(Data("{}".utf8)) }
        let unsafe = String(data: fixture(), encoding: .utf8)!.replacingOccurrences(of: "https://w.wallhaven.cc", with: "http://localhost")
        #expect(throws: OpenpaperError.self) { try WallhavenClient.decodeListing(Data(unsafe.utf8)) }
    }
    @Test func authHeaderAndHotContract() async throws {
        MockURLProtocol.handler { request in
            #expect(request.value(forHTTPHeaderField: "X-API-Key") == "test-key")
            #expect(request.url?.query?.contains("apikey") == false)
            #expect(request.url?.query?.contains("sorting=hot") == true)
            return .init()
        }
        let client = MockURLProtocol.client(); await client.configure(key: "test-key", policy: .init())
        var options = WallhavenSearchOptions(); options.sorting = .hot
        let page = try await client.search(options, page: 1, seed: nil)
        #expect(page.wallpapers.count == 1)
    }
    @Test func authenticationAndRateLimitErrors() async throws {
        MockURLProtocol.handler { _ in .init(status: 401) }
        let client = MockURLProtocol.client()
        await #expect(throws: OpenpaperError.unauthorized) { try await client.search(.init(), page: 1, seed: nil) }
        MockURLProtocol.handler { _ in .init(status: 429, headers: ["Retry-After": "2"]) }
        await #expect(throws: OpenpaperError.rateLimited(2)) { try await client.search(.init(), page: 1, seed: nil) }
    }
    @Test @MainActor func lateSearchCannotReplaceNewResults() async throws {
        MockURLProtocol.handler { request in
            request.url?.query?.contains("q=slow") == true ? .init(data: fixture(id: "slow12"), delay: .milliseconds(200)) : .init(data: fixture(id: "fast12"))
        }
        let client = MockURLProtocol.client(), feed = SearchFeed()
        feed.options.query = "slow"
        let slow = Task { await feed.refresh(client: client) }
        try await Task.sleep(for: .milliseconds(30))
        feed.options.query = "fast"; await feed.refresh(client: client)
        await slow.value
        #expect(feed.results.map(\.id) == ["fast12"]); #expect(!feed.loading)
    }
    @Test @MainActor func paginationKeepsSeedAndDeduplicates() async throws {
        MockURLProtocol.handler { request in
            if request.url?.query?.contains("page=2") == true {
                #expect(request.url?.query?.contains("seed=Ab1234") == true)
                return .init(data: fixture(page: 2, seed: "Other1"))
            }
            return .init()
        }
        let feed = SearchFeed(); feed.options.sorting = .random; let client = MockURLProtocol.client()
        await feed.refresh(client: client); await feed.next(client: client)
        #expect(feed.results.count == 1); #expect(feed.currentPage == 2); #expect(feed.seed == "Ab1234")
        feed.options.query = "changed"; #expect(feed.needsRefresh)
        await feed.refresh(client: client); #expect(feed.currentPage == 1)
    }
    @Test @MainActor func transferMergesWithoutLosingDownloads() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try LibraryStore(inMemory: true, root: root.appendingPathComponent("source"))
        let target = try LibraryStore(inMemory: true, root: root.appendingPathComponent("target"))
        let w = wallpaper()
        try source.toggleFavorite(w); try source.createCollection(name: "Paisajes")
        try source.add([w], to: #require(source.collections.first)); try source.saveSearch(name: "Paisajes", options: .init())
        try target.markDownloaded(w, fileName: "wallhaven-abc123.jpg")
        let data = try source.exportData(); let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("fileName")); #expect(!text.contains(root.path)); #expect(!text.contains("apikey"))
        try target.importData(data); try target.importData(data)
        #expect(target.items.count == 1); #expect(target.items.first?.favorite == true)
        #expect(target.items.first?.fileName == "wallhaven-abc123.jpg")
        #expect(target.collections.count == 1); #expect(target.searches.count == 1)
        var transfer = try JSONDecoder().decode(LibraryTransfer.self, from: data); transfer.version = 99
        #expect(throws: OpenpaperError.self) { try target.importData(JSONEncoder().encode(transfer)) }
        #expect(target.items.count == 1)
        transfer.version = 1; transfer.collections[0].keys.append("wallhaven:missing")
        #expect(throws: OpenpaperError.self) { try target.importData(JSONEncoder().encode(transfer)) }
        #expect(target.collections.first?.keys == [w.identity.key])
    }
    @Test @MainActor func persistenceReopensLocalLibrary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        do { let library = try LibraryStore(root: root); try library.toggleFavorite(wallpaper()); try library.createCollection(name: "Local") }
        let reopened = try LibraryStore(root: root)
        #expect(reopened.items.first?.favorite == true); #expect(reopened.collections.first?.name == "Local")
    }
    @Test func rotationExhaustsBeforeRepeatingAndEmptySources() {
        var rotation = RotationOrder()
        let firstCycle = (0..<3).compactMap { _ in rotation.next(ids: ["a", "b", "c"], random: true) }
        #expect(Set(firstCycle) == ["a", "b", "c"])
        #expect(rotation.next(ids: [], random: false) == nil)
        #expect(rotation.next(ids: ["d"], random: false) == "d")
        var sequential = RotationOrder()
        #expect(sequential.next(ids: ["a", "a", "b"], random: false) == "a")
        #expect(sequential.next(ids: ["a", "a", "b"], random: false) == "b")
    }
    @Test func cropStaysInsideOriginal() {
        let crop = CropGeometry(imageWidth: 4000, imageHeight: 2000, aspect: 1, zoom: 2, offsetX: 99, offsetY: -99)
        #expect(crop.width == 1000); #expect(crop.height == 1000); #expect(crop.x == 0); #expect(crop.y == 1000)
    }
    @Test func originalPreservedAndDerivedHasCorrectSize() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("original.png"), derived = root.appendingPathComponent("derived.jpg")
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
        let image = try #require(context.makeImage()), destination = try #require(CGImageDestinationCreateWithURL(original as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil); #expect(CGImageDestinationFinalize(destination))
        let before = try Data(contentsOf: original)
        #expect(throws: OpenpaperError.self) { try ImageProcessing.crop(original: original, output: original, aspect: 1, zoom: 1, offsetX: 0, offsetY: 0) }
        _ = try ImageProcessing.crop(original: original, output: derived, aspect: 1, zoom: 1, offsetX: 0, offsetY: 0)
        #expect(try Data(contentsOf: original) == before)
        let result = try ImageProcessing.thumbnail(url: derived, pixels: 400)
        #expect(result.cgImage.width == 200); #expect(result.cgImage.height == 200)
        let invalid = root.appendingPathComponent("invalid.jpg"); try Data("not an image".utf8).write(to: invalid)
        #expect(throws: OpenpaperError.self) { try ImageProcessing.validateOriginal(invalid) }
        let originals = root.appendingPathComponent("Originals")
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        let downloaded = originals.appendingPathComponent("wallhaven-abc123.png")
        try before.write(to: downloaded)
        var w = wallpaper(); w.fileType = "image/png"
        let downloader = DownloadService(root: root)
        let first = try await downloader.download(w), duplicate = try await downloader.download(w)
        #expect(first == duplicate); #expect(try Data(contentsOf: duplicate) == before)
        var unsafe = w; unsafe.path = URL(string: "http://127.0.0.1/private")!
        await #expect(throws: OpenpaperError.invalidResponse) { try await downloader.download(unsafe) }
        let unusableRoot = root.appendingPathComponent("not-a-directory")
        try Data().write(to: unusableRoot)
        await #expect(throws: (any Error).self) { try await DownloadService(root: unusableRoot).download(w) }
    }
    @Test func cancelledPermitDoesNotBlockQueue() async throws {
        let pool = PermitPool(limit: 1); try await pool.acquire()
        let waiting = Task { try await pool.acquire() }
        waiting.cancel(); await #expect(throws: CancellationError.self) { try await waiting.value }
        await pool.release(); try await pool.acquire(); await pool.release()
    }
}
