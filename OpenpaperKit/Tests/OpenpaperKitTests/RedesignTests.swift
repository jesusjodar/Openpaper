import Testing
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import OpenpaperKit
#if os(macOS)
import AppKit
import SwiftUI
import GlassBridge
#endif

private func sample(_ id: String, width: Int = 400, height: Int = 200) -> Wallpaper {
    Wallpaper(id: id, url: URL(string: "https://wallhaven.cc/w/\(id)")!, path: URL(string: "https://w.wallhaven.cc/full/ab/wallhaven-\(id).png")!, thumbnail: URL(string: "https://th.wallhaven.cc/lg/ab/\(id).jpg")!, width: width, height: height, fileType: "image/png")
}
private func makePNG(_ file: URL) throws -> Data {
    let context = try #require(CGContext(data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    context.setFillColor(CGColor(red: 0.1, green: 0.7, blue: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
    let image = try #require(context.makeImage()), destination = try #require(CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil); #expect(CGImageDestinationFinalize(destination))
    return try Data(contentsOf: file)
}
private actor Counter {
    var starts = 0
    var active = 0
    var peak = 0
    func start() { starts += 1 }
    func begin() { active += 1; peak = max(peak, active) }
    func end() { active -= 1 }
}
private func awaitConsumers(_ cache: MediaCache, _ url: URL, _ count: Int) async throws {
    for _ in 0..<200 {
        if await cache.activeConsumers(url: url) == count { return }
        try await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("Expected \(count) consumers")
}

@Suite struct RedesignTests {
    @Test func masonryKeepsAspectAndPaginationPrefix() {
        let first = [sample("first1", width: 400, height: 100), sample("first2", width: 100, height: 400), sample("first3"), sample("first4")]
        let a = MasonryColumns(wallpapers: first, available: 452, minimum: 220)
        let b = MasonryColumns(wallpapers: first + [sample("second")], available: 452, minimum: 220)
        #expect(a.columns.count == 2); #expect(a.width == 220)
        #expect(a.columns[0].map(\.id) == ["first1", "first3", "first4"])
        #expect(a.columns[1].map(\.id) == ["first2"])
        for index in a.columns.indices { #expect(Array(b.columns[index].prefix(a.columns[index].count)) == a.columns[index]) }
        #expect(a.height == 880)
        let narrow = MasonryColumns(wallpapers: first, available: 120, minimum: 220)
        #expect(narrow.columns.count == 1); #expect(narrow.columns[0] == first)
        #expect(MasonryColumns(wallpapers: [], available: 0, minimum: 220).height == 0)
    }
    @Test func retinaSizingNeverEnlargesSmallImages() {
        #expect(ImagePresentation.pixels(size: CGSize(width: 200, height: 400), scale: 3, sourceWidth: 2000, sourceHeight: 4000) == 1200)
        #expect(ImagePresentation.pixels(size: CGSize(width: 200, height: 400), scale: 3, sourceWidth: 100, sourceHeight: 200) == 200)
        #expect(ImagePresentation.fittedSize(image: CGSize(width: 100, height: 200), available: CGSize(width: 200, height: 400), scale: 2) == CGSize(width: 50, height: 100))
        #expect(ImagePresentation.pixels(size: CGSize(width: 400, height: 800), scale: 3, sourceWidth: 6000, sourceHeight: 3000, fill: true) == 4800)
        #expect(ImagePresentation.fittedSize(image: CGSize(width: 100, height: 200), available: CGSize(width: 200, height: 400), scale: 2, fill: true) == CGSize(width: 50, height: 100))
        #expect(ImagePresentation.fittedSize(image: CGSize(width: 2560, height: 1440), available: CGSize(width: 402, height: 874), scale: 3, fill: true, allowUpscale: true).height == 874)
    }
    @Test func originalIsSharedAcrossSizesAndExplicitDownload() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let data = try makePNG(root.appendingPathComponent("fixture.png")), count = Counter()
        let media = MediaCache(directory: root.appendingPathComponent("cache")) { _, destination, _, _, _ in
            await count.start(); try await Task.sleep(for: .milliseconds(30)); try data.write(to: destination); return destination
        }
        let pipeline = ImagePipeline(directory: root.appendingPathComponent("cache"), media: media), w = sample("abc123")
        let download = DownloadService(root: root.appendingPathComponent("library"), media: media)
        async let small = pipeline.image(url: w.path, maxPixel: 100, original: true)
        async let large = pipeline.image(url: w.path, maxPixel: 900, original: true)
        async let original = download.download(w)
        let (a, b, file) = try await (small, large, original)
        #expect(a.cgImage.width == 100); #expect(b.cgImage.width == 400)
        #expect(await count.starts == 1); #expect(try Data(contentsOf: file) == data)
        #expect(file.path.contains("library/Originals"))
        await pipeline.clearMemory()
        _ = try await pipeline.image(url: w.path, maxPixel: 150, original: true)
        #expect(await count.starts == 1)
        try await pipeline.clearDisk()
        #expect(try Data(contentsOf: file) == data)
    }
    @Test func previewsDoNotCreateLibraryFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let data = try makePNG(root.appendingPathComponent("fixture.png"))
        let media = MediaCache(directory: root.appendingPathComponent("cache")) { _, target, _, _, _ in try data.write(to: target); return target }
        _ = try await ImagePipeline(directory: root, media: media).image(url: sample("abc123").path, maxPixel: 200, original: true)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Originals").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("library").path))
    }
    @Test func originalTransfersStayLimitedToTwoAndReuseLegacyResume() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let resume = root.appendingPathComponent("old.resume"), bytes = Data("previous resume".utf8), count = Counter()
        try bytes.write(to: resume)
        let media = MediaCache(directory: root.appendingPathComponent("cache")) { _, target, restored, _, _ in
            #expect(try Data(contentsOf: restored) == bytes)
            await count.begin(); try await Task.sleep(for: .milliseconds(20)); await count.end()
            try Data("source".utf8).write(to: target); return target
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for id in ["aaa111", "bbb222", "ccc333", "ddd444"] {
                group.addTask { _ = try await media.withFile(url: sample(id).path, original: true, previousResume: resume) { $0 } }
            }
            try await group.waitForAll()
        }
        #expect(await count.peak == 2); #expect(await count.active == 0)
        #expect(try Data(contentsOf: resume) == bytes)
    }
    @Test func cancellationKeepsOtherConsumersAndStopsLastTransfer() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let count = Counter(), url = sample("abc123").path
        let media = MediaCache(directory: root) { _, target, _, _, _ in
            await count.start(); try await Task.sleep(for: .milliseconds(100)); try Data("shared".utf8).write(to: target); return target
        }
        let first = Task { try await media.withFile(url: url, original: true) { try Data(contentsOf: $0) } }
        let second = Task { try await media.withFile(url: url, original: true) { try Data(contentsOf: $0) } }
        try await awaitConsumers(media, url, 2); first.cancel()
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(try await second.value == Data("shared".utf8)); #expect(await count.starts == 1)
        let other = sample("def456").path
        let last = Task { try await media.withFile(url: other, original: true) { $0 } }
        try await awaitConsumers(media, other, 1); last.cancel()
        await #expect(throws: CancellationError.self) { try await last.value }
        #expect(await media.activeConsumers(url: other) == 0)
    }
    #if os(macOS)
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OPENPAPER_GLASS_SYSTEM_TEST"] == "1")) @MainActor func swiftUIContainerIncludesNativeGlass() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: -2000, y: -2000, width: 320, height: 240), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: NativeGlassContainer {
            GlassEffectContainer(spacing: 0) {
                VStack {
                    Button("Public glass") {}.buttonStyle(.glass)
                    HStack { ClearCardGlass(reducedTransparency: false); ClearCardGlass(reducedTransparency: false) }
                    Text("Public badge").glassEffect(.regular, in: Capsule())
                }
            }
        })
        window.contentView = host; window.layoutIfNeeded(); host.layoutSubtreeIfNeeded()
        func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
        let descendants = views(host)
        let container = try? #require(descendants.compactMap { $0 as? CardGlassContainerView }.first)
        #expect(container?.spacing == 0)
        let cards = descendants.compactMap { $0 as? CardGlassView }
        #expect(cards.count == 2)
        for card in cards { card.layoutSubtreeIfNeeded(); card.adjustMaterial(); #expect(card.adjustedFilterCount == 1) }
        let unrelated = NSGlassEffectView(); unrelated.style = .regular
        container?.contentView?.addSubview(unrelated); container?.material.adjustMaterial()
        #expect(container?.material.adjustedFilterCount == 0)
        unrelated.removeFromSuperview(); container?.material.adjustMaterial()
        #expect(container?.material.adjustedFilterCount == 1)
        window.contentView = nil; window.close()
        container?.material.stopObserving(); #expect(container?.material.observerCount == 0)
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OPENPAPER_GLASS_SYSTEM_TEST"] == "1")) @MainActor func masonryVirtualizesNativeMaterials() async throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: -2000, y: -2000, width: 600, height: 400), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let session = AppSession(), wallpapers = (0..<2000).map { sample(String(format: "a%05x", $0)) }
        let host = NSHostingView(rootView: NativeGlassContainer { MasonryScroll(session: session, wallpapers: wallpapers) })
        window.contentView = host; window.layoutIfNeeded(); host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        func cards(_ view: NSView) -> [CardGlassView] { (view as? CardGlassView).map { [$0] } ?? view.subviews.flatMap(cards) }
        let visible = cards(host)
        #expect(!visible.isEmpty); #expect(visible.count < 20)
        for card in visible { card.adjustMaterial(); #expect(card.adjustedFilterCount > 0) }
        window.contentView = nil; window.close()
        #expect(visible.allSatisfy { $0.observerCount == 0 })
    }
    @Test @MainActor func glassBridgeChangesOnlyVerifiedKeysAndCatchesKVCExceptions() {
        let filter = ProbeFilter()
        let before = OPReadBlurValues(filter)
        #expect(before?["inputBlurRadius"] as? NSNumber == 8); #expect(before?["inputBlurOpacity0"] as? NSNumber == 0.7)
        #expect(OPWriteBlurValues(filter, ["inputBlurRadius": 0, "inputBlurOpacity0": 0]))
        #expect(filter.inputBlurRadius == 0); #expect(filter.inputBlurOpacity0 == 0)
        #expect(filter.inputShadowBlurRadius == 12)
        #expect(!OPWriteBlurValues(filter, ["inputShadowBlurRadius": 0]))
        filter.inputKeys = ["inputBlurRadius"]
        #expect(OPReadBlurValues(filter) == nil)
        filter.inputKeys = ["inputBlurRadius", "inputBlurOpacityMissing"]
        #expect(OPReadBlurValues(filter) == nil)
        let readOnly = ReadOnlyProbe()
        #expect(!OPWriteBlurValues(readOnly, ["inputBlurRadius": 0, "inputBlurOpacity0": 0]))
        #expect(readOnly.inputBlurRadius == 8)
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OPENPAPER_GLASS_SYSTEM_TEST"] == "1")) @MainActor func nativeMaterialReappliesAndRemovesObservers() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: -2000, y: -2000, width: 320, height: 240), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = CardGlassView(); window.contentView = view; window.layoutIfNeeded(); view.adjustMaterial()
        #expect(view.adjustedFilterCount > 0); #expect(view.observerCount > 0)
        view.style = .regular; view.layoutSubtreeIfNeeded(); view.style = .clear; view.layoutSubtreeIfNeeded(); view.adjustMaterial()
        #expect(view.adjustedFilterCount > 0)
        view.reducedTransparency = true; view.adjustMaterial(); #expect(view.adjustedFilterCount == 0)
        window.contentView = nil; view.stopObserving(); #expect(view.observerCount == 0)
        window.close()
    }
    #endif
}
#if os(macOS)
@MainActor private final class ProbeFilter: NSObject {
    @objc dynamic var inputKeys = ["inputBlurRadius", "inputBlurOpacity0", "inputShadowBlurRadius"]
    @objc dynamic var inputBlurRadius: NSNumber = 8
    @objc dynamic var inputBlurOpacity0: NSNumber = 0.7
    @objc dynamic var inputShadowBlurRadius: NSNumber = 12
}
@MainActor private final class ReadOnlyProbe: NSObject {
    @objc var inputKeys: [String] { ["inputBlurRadius", "inputBlurOpacity0"] }
    @objc var inputBlurRadius: NSNumber { 8 }
    @objc var inputBlurOpacity0: NSNumber { 0.7 }
    override func setValue(_ value: Any?, forKey key: String) { NSException(name: .invalidArgumentException, reason: "Read only").raise() }
}
#endif
