import SwiftUI
import UniformTypeIdentifiers

struct MasonryColumns {
    let columns: [[Wallpaper]]
    let width: CGFloat
    let height: CGFloat
    init(wallpapers: [Wallpaper], available: CGFloat, minimum: CGFloat, spacing: CGFloat = 12) {
        let count = max(1, Int((max(1, available) + spacing) / (minimum + spacing)))
        width = max(1, (available - CGFloat(count - 1) * spacing) / CGFloat(count))
        var columns = Array(repeating: [Wallpaper](), count: count), heights = Array(repeating: CGFloat.zero, count: count)
        for wallpaper in wallpapers {
            let column = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            if !columns[column].isEmpty { heights[column] += spacing }
            columns[column].append(wallpaper); heights[column] += width / wallpaper.displayAspect
        }
        self.columns = columns; height = heights.max() ?? 0
    }
}

extension Wallpaper {
    var displayAspect: CGFloat { width > 0 && height > 0 ? CGFloat(width) / CGFloat(height) : 1 }
}

enum ImagePresentation {
    static func pixels(size: CGSize, scale: CGFloat, sourceWidth: Int, sourceHeight: Int, zoom: CGFloat = 1, fill: Bool = false) -> Int {
        let aspect = sourceWidth > 0 && sourceHeight > 0 ? CGFloat(sourceWidth) / CGFloat(sourceHeight) : 1
        let presentation = fill ? CGSize(width: max(size.width, size.height * aspect), height: max(size.height, size.width / aspect)) : size
        let wanted = max(presentation.width, presentation.height) * max(1, scale) * max(1, zoom)
        let native = max(sourceWidth, sourceHeight)
        return max(1, Int(ceil(native > 0 ? min(CGFloat(native), wanted) : wanted)))
    }
    static func fittedSize(image: CGSize, available: CGSize, scale: CGFloat, fill: Bool = false, allowUpscale: Bool = false) -> CGSize {
        let native = CGSize(width: image.width / max(1, scale), height: image.height / max(1, scale))
        let horizontal = available.width / max(1, native.width), vertical = available.height / max(1, native.height)
        let fit = fill ? max(horizontal, vertical) : min(horizontal, vertical)
        let factor = allowUpscale ? fit : min(1, fit)
        return CGSize(width: native.width * factor, height: native.height * factor)
    }
}

struct WallpaperImage: View {
    var session: AppSession
    let wallpaper: Wallpaper
    var file: URL? = nil
    var requestOriginal = false
    var fill = false
    var zoom: CGFloat = 1
    var loaded: ((RenderedImage) -> Void)? = nil
    @Environment(\.displayScale) private var scale
    @State private var image: RenderedImage?
    @State private var failed = false
    @State private var visible = false
    @State private var qualityFailed = false
    @State private var attempt = 0
    private struct Request: Hashable { var url: URL; var pixels: Int; var original: Bool; var visible: Bool; var attempt: Int }
    var body: some View {
        GeometryReader { geometry in
            let source = file ?? session.library?.localURL(wallpaper)
            let pixels = ImagePresentation.pixels(size: geometry.size, scale: scale, sourceWidth: wallpaper.width, sourceHeight: wallpaper.height, zoom: zoom, fill: fill)
            let request = Request(url: source ?? wallpaper.path, pixels: pixels, original: requestOriginal || session.allowOriginalPreviews, visible: visible, attempt: attempt)
            ZStack {
                Rectangle().fill(.quaternary)
                if let image {
                    let size = ImagePresentation.fittedSize(image: CGSize(width: image.cgImage.width, height: image.cgImage.height), available: geometry.size, scale: scale, fill: fill, allowUpscale: requestOriginal)
                    Image(decorative: image.cgImage, scale: scale).resizable().interpolation(.high)
                        .frame(width: size.width, height: size.height)
                } else if failed { Button("Reintentar imagen", systemImage: "arrow.clockwise") { attempt += 1 }.buttonStyle(.glass) }
                else { ProgressView() }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
                .overlay(alignment: .topTrailing) {
                    if requestOriginal && qualityFailed {
                        Button("Reintentar calidad", systemImage: "arrow.clockwise") { attempt += 1 }.buttonStyle(.glass).padding(12)
                    }
                }
                .task(id: request) {
                    guard visible else { image = nil; return }
                    failed = false; qualityFailed = false
                    guard let pipeline = session.images else { return }
                    if let source {
                        do { try accept(await pipeline.image(url: source, maxPixel: pixels)) }
                        catch { if !Task.isCancelled { failed = image == nil } }
                        return
                    }
                    if image == nil {
                        do { try accept(await pipeline.image(url: wallpaper.thumbnail, maxPixel: pixels)) }
                        catch { if !Task.isCancelled { failed = true } }
                    }
                    guard request.original, !Task.isCancelled else { return }
                    do { try accept(await pipeline.image(url: wallpaper.path, maxPixel: pixels, original: true)) }
                    catch { if !Task.isCancelled { failed = image == nil; qualityFailed = true } }
                }
        }.onScrollVisibilityChange(threshold: 0.01) { visible = $0 }
            .onDisappear { visible = false; image = nil }
    }
    @MainActor private func accept(_ value: RenderedImage) throws {
        try Task.checkCancellation(); image = value; failed = false; loaded?(value)
    }
}

struct WallpaperGrid: View {
    var session: AppSession
    var wallpapers: [Wallpaper]
    var selecting = false
    @Binding var selection: Set<String>
    var width: CGFloat
    @Environment(\.horizontalSizeClass) private var sizeClass
    init(session: AppSession, wallpapers: [Wallpaper], width: CGFloat, selecting: Bool = false, selection: Binding<Set<String>> = .constant([])) {
        self.session = session; self.wallpapers = wallpapers; self.width = width; self.selecting = selecting; _selection = selection
    }
    private var layout: MasonryColumns { MasonryColumns(wallpapers: wallpapers.filter { session.policy.permits($0) }, available: max(1, width - 32), minimum: sizeClass == .compact ? 155 : 220) }
    var body: some View {
        let layout = layout
            GlassEffectContainer(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(layout.columns.indices, id: \.self) { column in
                    LazyVStack(spacing: 12) {
                        ForEach(layout.columns[column], id: \.identity) { wallpaper in
                            card(wallpaper).id(wallpaper.identity.key)
                                .frame(width: layout.width, height: layout.width / wallpaper.displayAspect)
                                .accessibilitySortPriority(Double(wallpapers.count - (wallpapers.firstIndex(of: wallpaper) ?? 0)))
                        }
                    }.frame(width: layout.width).scrollTargetLayout()
                }
            }.padding(.horizontal, 16)
            }
        .frame(height: layout.height, alignment: .top)
            .padding(.vertical, 12)
    }
    private func card(_ wallpaper: Wallpaper) -> some View {
        Group {
            if selecting {
                Button {
                    if selection.contains(wallpaper.identity.key) { selection.remove(wallpaper.identity.key) }
                    else { selection.insert(wallpaper.identity.key) }
                } label: { WallpaperCard(session: session, wallpaper: wallpaper, selecting: true, selected: selection.contains(wallpaper.identity.key)) }
                .accessibilityAddTraits(selection.contains(wallpaper.identity.key) ? .isSelected : [])
            } else { NavigationLink(value: wallpaper) { WallpaperCard(session: session, wallpaper: wallpaper) } }
        }.buttonStyle(.plain)
        .contextMenu {
            Button(session.library?.item(wallpaper)?.favorite == true ? "Quitar de favoritos" : "Añadir a favoritos", systemImage: "heart") { session.perform { try session.library?.toggleFavorite(wallpaper) } }
            Button("Descargar original", systemImage: "arrow.down.circle") { Task { do { _ = try await session.download(wallpaper) } catch { session.message = error.localizedDescription } } }
            if let library = session.library, !library.collections.isEmpty {
                Menu("Añadir a colección") { ForEach(library.collections) { collection in Button(collection.name) { session.perform { try library.add([wallpaper], to: collection) } } } }
            }
            ShareLink(item: wallpaper.url) { Label("Compartir enlace", systemImage: "square.and.arrow.up") }
        }
        .onDrag {
            if let file = session.library?.localURL(wallpaper), let provider = NSItemProvider(contentsOf: file) { return provider }
            return NSItemProvider(object: wallpaper.url as NSURL)
        }
    }
}

private struct WallpaperCard: View {
    var session: AppSession
    let wallpaper: Wallpaper
    var selecting = false
    var selected = false
    @State private var visible = false
    var body: some View {
        ZStack {
            WallpaperImage(session: session, wallpaper: wallpaper)
            if visible { CardGlass(decoration: AnyView(badges.accessibilityHidden(true))).allowsHitTesting(false) }
        }.clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Fondo \(wallpaper.id), \(wallpaper.resolution), \(wallpaper.category), \(wallpaper.purity)\(session.library?.item(wallpaper)?.favorite == true ? ", favorito" : "")\(session.library?.localURL(wallpaper) != nil ? ", descargado" : "")\(selected ? ", seleccionado" : "")")
            .onScrollVisibilityChange(threshold: 0.01) { visible = $0 }
            .onDisappear { visible = false }
    }
    private var badges: some View {
        Color.clear
            .overlay(alignment: .bottomLeading) {
                if visible {
                HStack(spacing: 6) {
                    Text(wallpaper.resolution).monospacedDigit()
                    if session.library?.item(wallpaper)?.favorite == true { Image(systemName: "heart.fill").foregroundStyle(.red) }
                    if session.library?.localURL(wallpaper) != nil { Image(systemName: "arrow.down.circle.fill") }
                    #if os(macOS)
                    if let file = session.library?.localURL(wallpaper), session.application.isApplied(file) { Image(systemName: "desktopcomputer") }
                    #endif
                }.font(.caption).padding(8).glassEffect(.regular, in: Capsule()).padding(24)
                }
            }
            .overlay(alignment: .topTrailing) {
                if visible && selecting { Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.title2).padding(8).glassEffect(.regular, in: Circle()).padding(24) }
            }
    }
}

struct MasonryScroll<Footer: View>: View {
    var session: AppSession
    var wallpapers: [Wallpaper]
    var selecting = false
    @Binding var selection: Set<String>
    @ViewBuilder var footer: () -> Footer
    @State private var anchor: String?
    @State private var width: CGFloat = 0
    init(session: AppSession, wallpapers: [Wallpaper], selecting: Bool = false, selection: Binding<Set<String>> = .constant([]), @ViewBuilder footer: @escaping () -> Footer = { EmptyView() }) {
        self.session = session; self.wallpapers = wallpapers; self.selecting = selecting; _selection = selection; self.footer = footer
    }
    var body: some View {
        GeometryReader { geometry in
        ScrollViewReader { proxy in
        ScrollView {
            WallpaperGrid(session: session, wallpapers: wallpapers, width: geometry.size.width, selecting: selecting, selection: $selection)
            footer()
        }.scrollPosition(id: $anchor, anchor: .top)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newWidth in
                let visible = anchor
                if width > 0, width != newWidth, let visible { Task { @MainActor in await Task.yield(); proxy.scrollTo(visible, anchor: .top) } }
                width = newWidth
            }
        }
        }
    }
}
