import SwiftUI
import UniformTypeIdentifiers

struct DetailView: View {
    @Bindable var session: AppSession
    @State var wallpaper: Wallpaper
    @Environment(\.dismiss) private var dismiss
    @State private var heroImage: RenderedImage?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var detailError: String?
    @State private var detailLoaded = false
    @State private var remote = false
    @State private var crop = false
    @State private var derived: URL?
    @State private var zoom: CGFloat = 1
    @State private var zoomStart: CGFloat = 1
    @State private var exporter = false
    @State private var document: ImageDocument?
    @State private var exportingType: UTType = .jpeg
    @State private var working = false
    @State private var target = ""
    @State private var fill = true
    @State private var photosInstructions = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ScaledMetric(relativeTo: .largeTitle) private var compactTitleSize: CGFloat = 42
    @ScaledMetric(relativeTo: .largeTitle) private var regularTitleSize: CGFloat = 64
    private var file: URL? { derived ?? session.library?.localURL(wallpaper) }
    private var favorite: Bool { session.library?.item(wallpaper)?.favorite == true }
    var body: some View {
        if session.policy.permits(wallpaper) { detailContent }
        else { ContentUnavailableView("Contenido desactivado", systemImage: "eye.slash", description: Text("Este fondo ya no cumple el contenido permitido en Ajustes.")) }
    }
    private var detailContent: some View {
        GeometryReader { viewport in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero(size: viewport.size)
                VStack(alignment: .leading, spacing: 20) {
                    if derived != nil { Label("Usando una copia encuadrada. El original se conserva.", systemImage: "crop").font(.caption) }
                    if let progress = session.jobs[wallpaper.identity.key] {
                        HStack { ProgressView(value: progress).accessibilityLabel("Descargando original"); Text(progress, format: .percent.precision(.fractionLength(0))).monospacedDigit(); GlassIconButton(title: "Cancelar descarga", symbol: "xmark") { session.cancelDownload(wallpaper) } }
                    }
                    if let error = session.downloadErrors[wallpaper.identity.key] { HStack { Text(error); GlassIconButton(title: "Reintentar descarga", symbol: "arrow.clockwise") { download() } } }
                    if let detailError { HStack { Text(detailError); GlassIconButton(title: "Reintentar detalle", symbol: "arrow.clockwise") { Task { await loadDetail() } } } }
                    #if os(macOS)
                    HStack {
                        Picker("Monitor", selection: $target) {
                            Text("Todos los conectados").tag("")
                            ForEach(session.application.screens) { Text("\($0.name) · \($0.width) × \($0.height)").tag($0.id) }
                        }
                        Picker("Ajuste", selection: $fill) { Text("Rellenar").tag(true); Text("Ajustar").tag(false) }
                    }
                    #endif
                    if working { ProgressView("Preparando imagen…") }
                if let library = session.library {
                    GroupBox("Colecciones locales") {
                        if library.collections.isEmpty { Text("Crea una colección en Biblioteca.").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                        else {
                            VStack(alignment: .leading) {
                                ForEach(library.collections) { collection in
                                    Toggle(collection.name, isOn: Binding(get: { collection.keys.contains(wallpaper.identity.key) }, set: { selected in
                                        session.perform {
                                            if selected { try library.add([wallpaper], to: collection) }
                                            else { try library.remove(keys: [wallpaper.identity.key], from: collection) }
                                        }
                                    }))
                                }
                            }.padding(4)
                        }
                    }
                }
                GroupBox("Información") {
                    VStack(alignment: .leading, spacing: 8) {
                        info("Resolución", wallpaper.resolution)
                        info("Formato", wallpaper.fileType)
                        info("Tamaño", ByteCountFormatter.string(fromByteCount: Int64(wallpaper.fileSize), countStyle: .file))
                        info("Categoría", wallpaper.category)
                        info("Contenido", wallpaper.purity.uppercased())
                        info("Visitas / favoritos remotos", "\(wallpaper.views) / \(wallpaper.favorites)")
                        info("Proveedor", "Wallhaven")
                    }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).padding(4)
                }
                if !wallpaper.tags.isEmpty {
                    GroupBox("Etiquetas") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], alignment: .leading) {
                            ForEach(wallpaper.tags) { tag in Button(tag.name) { session.searchFor("id:\(tag.id)"); dismiss() }.buttonStyle(.glass).buttonBorderShape(.capsule) }
                        }.padding(4)
                    }
                }
                if !wallpaper.colors.isEmpty {
                    GroupBox("Colores") {
                        ScrollView(.horizontal) {
                            HStack { ForEach(wallpaper.colors, id: \.self) { hex in
                                Label(hex, systemImage: "circle.fill").font(.caption).foregroundStyle(Color(hex: hex)).accessibilityLabel("Color \(hex)")
                            } }
                        }.padding(4)
                    }
                }
                if let uploader = wallpaper.uploader {
                    Button("Ver fondos de \(uploader)", systemImage: "person") { session.searchFor("@\(uploader)"); dismiss() }
                    Button("Colecciones públicas de \(uploader)", systemImage: "folder") { remote = true }
                }
                Button("Fondos similares", systemImage: "photo.on.rectangle") { session.searchFor("like:\(wallpaper.id)"); dismiss() }
                if let source = wallpaper.source, let url = URL(string: source), ["http", "https"].contains(url.scheme ?? "") { Link("Procedencia original ↗", destination: url) }
                Link("Abrir en Wallhaven ↗", destination: wallpaper.url)
                Text("Los favoritos y las colecciones de Wallhaven se modifican en su web. Cada imagen conserva los derechos de su autor.").font(.caption).foregroundStyle(.secondary)
                }
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background { ReflectedInformationBackground(image: heroImage) }
                .groupBoxStyle(InformationBoxStyle())
                .foregroundStyle(reduceTransparency || contrast == .increased ? Color.primary : Color.white)
            }.frame(maxWidth: .infinity)
        }
        }
        .ignoresSafeArea(.container, edges: .top)
        #if os(iOS)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        #else
        .navigationTitle("Fondo · \(wallpaper.id)")
        #endif
        .task { if !detailLoaded { await loadDetail() } }
        .sheet(isPresented: $remote) { RemoteCollectionsView(session: session, username: wallpaper.uploader ?? "") }
        .sheet(isPresented: $crop) {
            if let original = session.library?.localURL(wallpaper) { CropView(session: session, wallpaper: wallpaper, original: original) { derived = $0; zoom = 1; zoomStart = 1 } }
        }
        .fileExporter(isPresented: $exporter, document: document, contentType: exportingType, defaultFilename: "wallhaven-\(wallpaper.id)\(derived != nil ? "-encuadrado" : "")") { result in
            document = nil
            if case .failure(let error) = result { session.message = error.localizedDescription }
        }
        .alert("Usar como fondo en iPhone o iPad", isPresented: $photosInstructions) {
            Button("Entendido", role: .cancel) {}
        } message: { Text("1. Abre Fotos y selecciona la imagen guardada.\n2. Pulsa Compartir.\n3. Elige Usar como fondo de pantalla.\n\nTambién puedes usar las acciones de Openpaper en Atajos y conectar la imagen con la acción del sistema para establecer el fondo.") }
    }
    private func hero(size: CGSize) -> some View {
        let titleSize = sizeClass == .compact ? compactTitleSize : regularTitleSize
        let height = max(size.height, titleSize * 2 + 260)
        return ZStack {
            Color.black
            WallpaperImage(session: session, wallpaper: wallpaper, file: file, requestOriginal: true, fill: wallpaper.displayAspect >= 1 && derived == nil, zoom: zoom) { heroImage = $0 }
            .frame(width: size.width, height: height)
            .scaleEffect(zoom).clipped()
            .gesture(MagnifyGesture().onChanged { zoom = min(5, max(1, zoomStart * $0.magnification)) }.onEnded { _ in zoomStart = zoom })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Vista previa del fondo \(wallpaper.id), \(wallpaper.resolution)")
            .accessibilityAddTraits(.isImage)
            .accessibilityAction(named: "Ampliar") { zoom = min(5, zoom + 1) }
            .accessibilityAction(named: "Restablecer zoom") { zoom = 1; zoomStart = 1 }
            VStack(spacing: 22) {
                    Text("Fondo · \(wallpaper.id)")
                        .font(.system(size: titleSize, weight: .heavy))
                        .multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                    Text([wallpaper.resolution, wallpaper.extensionName.uppercased(), wallpaper.uploader].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    actions
                    if working { ProgressView("Preparando imagen…").tint(.white) }
                    if let progress = session.jobs[wallpaper.identity.key] { Text(progress, format: .percent.precision(.fractionLength(0))).monospacedDigit().accessibilityLabel("Descargando original") }
            }
            .multilineTextAlignment(.center).foregroundStyle(.white)
            .padding(24).frame(maxWidth: 920)
            .background { RadialGradient(colors: [.black.opacity(0.5), .black.opacity(0.12), .clear], center: .center, startRadius: 30, endRadius: max(240, size.width / 2)) }
            .shadow(color: .black.opacity(0.7), radius: 4, y: 2)
        }.frame(width: size.width, height: max(1, height)).clipped()
    }
    private var actions: some View {
        GlassEffectContainer(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { favoriteButton; editButton; applyButton; downloadButton; secondaryActions }
                VStack(spacing: 16) {
                    applyButton
                    HStack(spacing: 12) { favoriteButton; editButton; downloadButton; secondaryActions }
                }
            }
        }
    }
    private var applyButton: some View {
            #if os(macOS)
            return Button {
                performFileAction { url in
                    try session.application.apply(file: url, target: target.isEmpty ? nil : target, fill: fill)
                    session.notice = "Fondo aplicado al monitor elegido. macOS gestiona los Spaces."
                }
            } label: { Label("Aplicar fondo", systemImage: "desktopcomputer").font(.headline).padding(.horizontal, 22).frame(minHeight: 44) }
            .buttonStyle(.glass).buttonBorderShape(.capsule).disabled(working).help("Aplicar al monitor elegido")
            #else
            return Button {
                performFileAction { url in try await PhotosService.save(url); photosInstructions = true }
            } label: { Label("Guardar en Fotos", systemImage: "photo.badge.arrow.down").font(.headline).padding(.horizontal, 22).frame(minHeight: 44) }
            .buttonStyle(.glass).buttonBorderShape(.capsule).disabled(working)
            #endif
    }
    private var favoriteButton: some View {
            GlassIconButton(title: favorite ? "Quitar favorito" : "Añadir favorito", symbol: favorite ? "heart.fill" : "heart") { session.perform { try session.library?.toggleFavorite(wallpaper) } }.tint(favorite ? .red : nil)
    }
    private var editButton: some View {
            GlassIconButton(title: "Encuadrar una copia", symbol: "crop") { performFileAction { _ in crop = true } }.disabled(working)
    }
    @ViewBuilder private var downloadButton: some View {
            if session.jobs[wallpaper.identity.key] != nil {
                GlassIconButton(title: "Cancelar descarga", symbol: "xmark") { session.cancelDownload(wallpaper) }
            } else {
                GlassIconButton(title: session.library?.localURL(wallpaper) != nil ? "Original descargado" : "Descargar original", symbol: session.library?.localURL(wallpaper) != nil ? "checkmark" : "arrow.down") { download() }
                    .disabled(session.library?.localURL(wallpaper) != nil)
            }
    }
    private var secondaryActions: some View {
        Menu {
            Button("Exportar imagen", systemImage: "square.and.arrow.up") {
                performFileAction { url in
                    document = try await Task.detached { try ImageDocument(file: url) }.value
                    exportingType = document?.type ?? .jpeg; exporter = true
                }
            }.disabled(working)
            if let file { ShareLink("Compartir imagen", item: file) }
            ShareLink("Compartir enlace", item: wallpaper.url)
            #if os(macOS)
            Button("Volver al fondo anterior", systemImage: "arrow.uturn.backward") { session.perform { try session.application.restorePrevious() } }
            #else
            Button("Cómo usarlo como fondo", systemImage: "info") { photosInstructions = true }
            #endif
        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
        .buttonStyle(.glass).buttonBorderShape(.circle)
        .menuIndicator(.hidden).fixedSize()
        .help("Más acciones").accessibilityLabel("Más acciones")
    }
    private func info(_ title: String, _ value: String) -> some View { LabeledContent(title) { Text(value).fixedSize(horizontal: false, vertical: true) } }
    private func loadDetail() async {
        do { let loaded = try await session.client.detail(id: wallpaper.id); try Task.checkCancellation(); wallpaper = loaded; detailLoaded = true; detailError = nil }
        catch { if !Task.isCancelled { detailError = error.localizedDescription } }
    }
    private func download() {
        Task { do { _ = try await session.download(wallpaper) } catch { /* Inline progress provides retry and cancellation feedback. */ } }
    }
    private func performFileAction(_ action: @escaping @MainActor (URL) async throws -> Void) {
        working = true
        Task {
            defer { working = false }
            do {
                guard session.policy.permits(wallpaper) else { throw OpenpaperError.validation("Este fondo no cumple el contenido permitido.") }
                let url: URL; if let file { url = file } else { url = try await session.download(wallpaper) }
                guard session.policy.permits(wallpaper) else { throw OpenpaperError.validation("El contenido permitido cambió durante la descarga.") }
                try await action(url)
            }
            catch { session.message = error.localizedDescription }
        }
    }
}

extension Color {
    init(hex: String) {
        let n = UInt64(hex.replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0
        self.init(.sRGB, red: Double((n >> 16) & 255) / 255, green: Double((n >> 8) & 255) / 255, blue: Double(n & 255) / 255, opacity: 1)
    }
}

private struct CropView: View {
    var session: AppSession
    let wallpaper: Wallpaper
    let original: URL
    let use: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var aspect = 16.0 / 9
    @State private var zoom = 1.0
    @State private var zoomStart = 1.0
    @State private var offset = CGSize.zero
    @State private var offsetStart = CGSize.zero
    @State private var image: RenderedImage?
    @State private var saving = false
    @State private var error: String?
    private var targets: [ScreenTarget] {
        #if os(macOS)
        session.application.screens
        #else
        MobileScreenService.target.map { [$0] } ?? []
        #endif
    }
    private var targetPixels: (width: Int, height: Int) {
        if let target = targets.first(where: { abs($0.aspect - aspect) < 0.0001 }) { return (target.width, target.height) }
        return aspect >= 1 ? (1920, Int(1920 / aspect)) : (1080, Int(1080 / aspect))
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Pantalla de destino", selection: $aspect) {
                    Text("16:9").tag(16.0 / 9); Text("16:10").tag(16.0 / 10)
                    Text("9:16").tag(9.0 / 16); Text("4:3").tag(4.0 / 3); Text("3:4").tag(3.0 / 4)
                    ForEach(targets) { screen in Text("\(screen.name) · \(screen.width) × \(screen.height)").tag(screen.aspect) }
                }.padding(.horizontal)
                GeometryReader { geometry in
                    let viewport = geometry.size
                    if let image {
                        let iw = Double(image.cgImage.width), ih = Double(image.cgImage.height)
                        let scale = max(viewport.width / iw, viewport.height / ih) * zoom
                        Image(decorative: image.cgImage, scale: 1).resizable()
                            .frame(width: iw * scale, height: ih * scale)
                            .position(x: viewport.width / 2 + offset.width * viewport.width, y: viewport.height / 2 + offset.height * viewport.height)
                            .gesture(DragGesture().onChanged { gesture in
                                offset = clamped(CGSize(width: offsetStart.width + gesture.translation.width / viewport.width, height: offsetStart.height + gesture.translation.height / viewport.height), viewport: viewport, image: image)
                            }.onEnded { _ in offsetStart = offset })
                            .simultaneousGesture(MagnifyGesture().onChanged { value in
                                zoom = min(5, max(1, zoomStart * value.magnification)); offset = clamped(offset, viewport: viewport, image: image)
                            }.onEnded { _ in zoomStart = zoom; offsetStart = offset })
                    } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                }
                .aspectRatio(aspect, contentMode: .fit).clipped().padding(.horizontal)
                .accessibilityLabel("Encuadre de la imagen. Usa los controles de zoom y desplazamiento.")
                Form {
                    LabeledContent("Zoom") {
                        Slider(value: $zoom, in: 1...5) { Text("Zoom") }.onChange(of: zoom) { zoomStart = zoom; offset = normalized(offset); offsetStart = offset }
                    }
                    LabeledContent("Horizontal") {
                        Slider(value: Binding(get: { offset.width }, set: { offset = normalized(CGSize(width: $0, height: offset.height)); offsetStart = offset }), in: -2...2) { Text("Desplazamiento horizontal") }
                    }
                    LabeledContent("Vertical") {
                        Slider(value: Binding(get: { offset.height }, set: { offset = normalized(CGSize(width: offset.width, height: $0)); offsetStart = offset }), in: -2...2) { Text("Desplazamiento vertical") }
                    }
                    Button("Restablecer encuadre") { zoom = 1; zoomStart = 1; offset = .zero; offsetStart = .zero }
                    let bounds = CropGeometry(imageWidth: Double(wallpaper.width), imageHeight: Double(wallpaper.height), aspect: aspect, zoom: zoom, offsetX: offset.width, offsetY: offset.height)
                    Text("Copia: \(Int(bounds.width)) × \(Int(bounds.height)) píxeles").font(.caption)
                    if bounds.width < Double(targetPixels.width) || bounds.height < Double(targetPixels.height) { Label("La resolución puede ser insuficiente para \(targetPixels.width) × \(targetPixels.height) píxeles.", systemImage: "exclamationmark.triangle").font(.caption) }
                    Text("Previsualización orientativa: el sistema puede ajustar el resultado. El original se conserva.").font(.caption).foregroundStyle(.secondary)
                    if let error { Text(error).foregroundStyle(.red) }
                }.formStyle(.grouped)
            }
            .navigationTitle("Encuadrar una copia")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar copia") { save() }.disabled(image == nil || saving) }
            }
            .task {
                if let screen = targets.first { aspect = screen.aspect }
                do { image = try await session.images?.image(url: original, maxPixel: 2048) } catch { self.error = error.localizedDescription }
            }
            .onChange(of: aspect) { offset = .zero; offsetStart = .zero; zoom = 1; zoomStart = 1 }
        }
        #if os(macOS)
        .frame(width: 720, height: 820)
        #endif
    }
    private func clamped(_ offset: CGSize, viewport: CGSize, image: RenderedImage) -> CGSize {
        let scale = max(viewport.width / Double(image.cgImage.width), viewport.height / Double(image.cgImage.height)) * zoom
        let dx = max(0, (Double(image.cgImage.width) * scale - viewport.width) / (2 * viewport.width))
        let dy = max(0, (Double(image.cgImage.height) * scale - viewport.height) / (2 * viewport.height))
        return CGSize(width: min(dx, max(-dx, offset.width)), height: min(dy, max(-dy, offset.height)))
    }
    private func normalized(_ value: CGSize) -> CGSize {
        let imageAspect = image.map { Double($0.cgImage.width) / Double($0.cgImage.height) } ?? aspect
        let dx = max(0, (max(1, imageAspect / aspect) * zoom - 1) / 2)
        let dy = max(0, (max(1, aspect / imageAspect) * zoom - 1) / 2)
        return CGSize(width: min(dx, max(-dx, value.width)), height: min(dy, max(-dy, value.height)))
    }
    private func save() {
        guard let root = session.library?.root else { return }
        saving = true
        let aspect = aspect, zoom = zoom, offset = offset
        Task {
            do {
                let file = try await Task.detached {
                    let directory = root.appendingPathComponent("Derived", isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    return try ImageProcessing.crop(original: original, output: directory.appendingPathComponent("\(wallpaper.id)-\(UUID().uuidString).jpg"), aspect: aspect, zoom: zoom, offsetX: offset.width, offsetY: offset.height)
                }.value
                use(file); dismiss()
            } catch { self.error = error.localizedDescription; saving = false }
        }
    }
}

private struct InformationBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            configuration.label.font(.headline)
            configuration.content
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
    }
}

private struct ReflectedInformationBackground: View {
    var image: RenderedImage?
    @Environment(\.accessibilityReduceTransparency) private var reduced
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        GeometryReader { geometry in
            if reduced || contrast == .increased || image == nil {
                Rectangle().fill(.background)
            } else if let image {
                ZStack {
                    ForEach(0..<3) { band in
                        Image(decorative: image.cgImage, scale: 1).resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .scaleEffect(x: 1, y: -1).blur(radius: CGFloat(12 + band * 20))
                            .mask {
                                if band == 0 { LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom) }
                                else if band == 1 { LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.5), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom) }
                                else { LinearGradient(colors: [.clear, .white], startPoint: .top, endPoint: .bottom) }
                            }
                    }
                    Rectangle().fill(.black.opacity(0.65))
                }.clipped()
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
