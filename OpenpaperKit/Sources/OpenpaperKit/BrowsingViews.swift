import SwiftUI
import UniformTypeIdentifiers

public struct OpenpaperRoot: View {
    @Bindable var session: AppSession
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var settings = false
    @State private var path: [Wallpaper] = []
    public init(session: AppSession) { self.session = session }
    private var compact: Bool {
        #if os(macOS)
        false
        #else
        sizeClass == .compact
        #endif
    }
    public var body: some View {
        Group {
            if let error = session.startupError {
                ContentUnavailableView("No se pudo abrir la biblioteca", systemImage: "externaldrive.badge.exclamationmark", description: Text("\(error)\nLos archivos existentes se conservan. Cierra la app y revisa el espacio o los permisos antes de reabrirla."))
            } else if compact {
                TabView(selection: $session.destination) {
                    ForEach(Destination.allCases) { destination in
                        Tab(destination.rawValue, systemImage: destination.symbol, value: destination) {
                            NavigationStack { screen(destination).navigationDestination(for: Wallpaper.self) { DetailView(session: session, wallpaper: $0) } }
                        }
                    }
                }
            } else {
                NavigationSplitView {
                    List(selection: Binding<Destination?>(get: { session.destination }, set: { if let value = $0 { session.destination = value } })) {
                        ForEach(Destination.allCases) { destination in Label(destination.rawValue, systemImage: destination.symbol).tag(destination) }
                    }
                    .navigationTitle("Openpaper")
                    .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
                } detail: {
                    NavigationStack(path: $path) {
                        screen(session.destination).navigationDestination(for: Wallpaper.self) { DetailView(session: session, wallpaper: $0) }
                    }
                }
                .onChange(of: session.destination) { path.removeAll() }
            }
        }
        .task { await session.start() }
        .sheet(isPresented: $settings) { NavigationStack { SettingsView(session: session).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Hecho") { settings = false } } } } }
        .alert("No se pudo completar la acción", isPresented: Binding(get: { session.message != nil }, set: { if !$0 { session.message = nil } })) {
            Button("Aceptar") { session.message = nil }
        } message: { Text(session.message ?? "") }
        .alert("Openpaper", isPresented: Binding(get: { session.notice != nil }, set: { if !$0 { session.notice = nil } })) {
            Button("Aceptar") { session.notice = nil }
        } message: { Text(session.notice ?? "") }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { Task { await session.images?.clearMemory() } }
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            Task { await session.images?.clearMemory() }
        }
        #endif
    }
    @ViewBuilder private func screen(_ destination: Destination) -> some View {
        Group {
            switch destination {
            case .explore: DiscoveryView(session: session, feed: session.explore, isSearch: false)
            case .search: DiscoveryView(session: session, feed: session.search, isSearch: true)
            case .library: LibraryView(session: session)
            }
        }
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) { Button("Ajustes", systemImage: "gearshape") { settings = true } }
            #endif
        }
    }
}

struct DiscoveryView: View {
    @Bindable var session: AppSession
    @Bindable var feed: SearchFeed
    var isSearch: Bool
    @State private var filters = false
    @State private var savingSearch = false
    @State private var searchName = ""
    var body: some View {
        VStack(spacing: 0) {
            if !isSearch {
                Picker("Descubrir", selection: $feed.options.sorting) {
                    Text("Recientes").tag(SearchSorting.dateAdded)
                    Text("Populares").tag(SearchSorting.toplist)
                    Text("Tendencias").tag(SearchSorting.hot)
                    Text("Aleatorios").tag(SearchSorting.random)
                }
                .pickerStyle(.segmented).padding()
            }
            HStack {
                Text(feed.options.summary).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if feed.total > 0 { Text(feed.total, format: .number).font(.caption).foregroundStyle(.secondary).accessibilityLabel("\(feed.total) resultados en el servidor") }
            }.padding(.horizontal).padding(.bottom, 8)
            if isSearch && feed.results.isEmpty && !feed.loading && feed.options.query.isEmpty {
                List {
                    if !session.history.isEmpty {
                        Section("Búsquedas recientes") {
                            ForEach(session.history, id: \.self) { query in Button(query) { feed.options.query = query } }
                        }
                    }
                    if let library = session.library, !library.searches.isEmpty {
                        Section("Búsquedas guardadas") {
                            ForEach(library.searches) { search in Button(search.name) { if let options = search.options { session.useSearch(options) } } }
                        }
                    }
                    Section { Text("Busca etiquetas o usa +montaña -ciudad, @usuario, id:123, type:png o like:abc123.").foregroundStyle(.secondary) }
                }
            } else { SearchResultsView(session: session, feed: feed) }
        }
        .navigationTitle(isSearch ? "Buscar" : "Explorar")
        .modifier(SearchField(enabled: isSearch, text: $feed.options.query))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Filtros", systemImage: "line.3.horizontal.decrease") { filters = true }
                    .disabled(feed.remote != nil)
                if isSearch { Button("Guardar búsqueda", systemImage: "bookmark") { searchName = feed.options.query; savingSearch = true } }
                Button("Actualizar", systemImage: "arrow.clockwise") { Task { await feed.refresh(client: session.client, prefetch: session.allowPrefetch) } }
                    .disabled(feed.loading)
            }
        }
        .sheet(isPresented: $filters) {
            FiltersView(options: feed.options, policy: session.policy, hasKey: session.keyValidated) { options in
                feed.options = options
            }
        }
        .alert("Guardar búsqueda", isPresented: $savingSearch) {
            TextField("Nombre", text: $searchName)
            Button("Guardar") { session.perform { try session.library?.saveSearch(name: searchName, options: feed.options) } }
            Button("Cancelar", role: .cancel) {}
        }
        .task(id: feed.options) {
            guard feed.needsRefresh else { return }
            if isSearch {
                do { try await Task.sleep(for: .milliseconds(350)); try Task.checkCancellation() } catch { return }
                session.recordSearch()
                if !feed.options.query.isEmpty { await feed.refresh(client: session.client, prefetch: session.allowPrefetch) }
                else { feed.clear() }
            } else {
                await feed.refresh(client: session.client, prefetch: session.allowPrefetch)
            }
        }
    }
}

private struct SearchField: ViewModifier {
    var enabled: Bool
    @Binding var text: String
    @ViewBuilder func body(content: Content) -> some View {
        if enabled { content.searchable(text: $text, prompt: "Etiquetas, usuario o consulta avanzada") }
        else { content }
    }
}

struct SearchResultsView: View {
    var session: AppSession
    @Bindable var feed: SearchFeed
    var body: some View {
        Group {
            if feed.results.isEmpty && feed.loading { ProgressView("Cargando fondos…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if feed.results.isEmpty, let error = feed.error {
                VStack { ContentUnavailableView("No se pudieron cargar los fondos", systemImage: "wifi.exclamationmark", description: Text(error))
                    Button("Reintentar") { Task { await feed.refresh(client: session.client, prefetch: session.allowPrefetch) } }.padding() }
            } else if feed.results.isEmpty { ContentUnavailableView("Sin resultados", systemImage: "photo", description: Text("Prueba otra consulta o revisa los filtros.")) }
            else {
                ScrollView {
                    WallpaperGrid(session: session, wallpapers: feed.results)
                    if let error = feed.error { Text(error).foregroundStyle(.red).padding() }
                    if feed.currentPage < feed.lastPage {
                        Button("Cargar más · página \(feed.currentPage + 1) de \(feed.lastPage)") { Task { await feed.next(client: session.client, prefetch: session.allowPrefetch) } }
                            .disabled(feed.loading).padding()
                    }
                    if feed.loading { ProgressView().padding() }
                }
                .refreshable { await feed.refresh(client: session.client, prefetch: session.allowPrefetch) }
            }
        }
    }
}

struct WallpaperGrid: View {
    var session: AppSession
    var wallpapers: [Wallpaper]
    var selecting = false
    @Binding var selection: Set<String>
    init(session: AppSession, wallpapers: [Wallpaper], selecting: Bool = false, selection: Binding<Set<String>> = .constant([])) {
        self.session = session; self.wallpapers = wallpapers; self.selecting = selecting; _selection = selection
    }
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 155, maximum: 300), spacing: 12)], spacing: 16) {
            ForEach(wallpapers.filter { session.policy.permits($0) }, id: \.identity) { wallpaper in
                Group {
                    if selecting {
                        Button {
                            if selection.contains(wallpaper.identity.key) { selection.remove(wallpaper.identity.key) }
                            else { selection.insert(wallpaper.identity.key) }
                        } label: { tile(wallpaper) }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selection.contains(wallpaper.identity.key) ? .isSelected : [])
                    } else { NavigationLink(value: wallpaper) { tile(wallpaper) }.buttonStyle(.plain) }
                }
                .contextMenu {
                    Button(session.library?.item(wallpaper)?.favorite == true ? "Quitar de favoritos" : "Añadir a favoritos", systemImage: "heart") {
                        session.perform { try session.library?.toggleFavorite(wallpaper) }
                    }
                    Button("Descargar original", systemImage: "arrow.down.circle") {
                        Task { do { _ = try await session.download(wallpaper) } catch { session.message = error.localizedDescription } }
                    }
                    if let library = session.library, !library.collections.isEmpty {
                        Menu("Añadir a colección") {
                            ForEach(library.collections) { collection in Button(collection.name) { session.perform { try library.add([wallpaper], to: collection) } } }
                        }
                    }
                    ShareLink(item: wallpaper.url) { Label("Compartir enlace", systemImage: "square.and.arrow.up") }
                }
                .onDrag {
                    if let file = session.library?.localURL(wallpaper), let provider = NSItemProvider(contentsOf: file) { return provider }
                    return NSItemProvider(object: wallpaper.url as NSURL)
                }
            }
        }.padding()
    }
    private func tile(_ wallpaper: Wallpaper) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Thumbnail(pipeline: session.images, url: session.library?.localURL(wallpaper) ?? wallpaper.thumbnail, pixels: 720)
                .frame(height: 150).frame(maxWidth: .infinity).clipped().clipShape(.rect(cornerRadius: 8))
                .overlay(alignment: .topTrailing) {
                    if selecting { Image(systemName: selection.contains(wallpaper.identity.key) ? "checkmark.circle.fill" : "circle").font(.title2).padding(8).foregroundStyle(.white).shadow(radius: 2) }
                }
            HStack(spacing: 6) {
                Text(wallpaper.resolution).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if session.library?.item(wallpaper)?.favorite == true { Image(systemName: "heart.fill").foregroundStyle(.red) }
                if session.library?.localURL(wallpaper) != nil { Image(systemName: "arrow.down.circle.fill").foregroundStyle(.secondary) }
                #if os(macOS)
                if let file = session.library?.localURL(wallpaper), session.application.isApplied(file) { Image(systemName: "desktopcomputer").foregroundStyle(.secondary) }
                #endif
            }.font(.caption)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fondo \(wallpaper.id), \(wallpaper.resolution), \(wallpaper.category), \(wallpaper.purity)\(session.library?.item(wallpaper)?.favorite == true ? ", favorito" : "")\(session.library?.localURL(wallpaper) != nil ? ", descargado" : "")")
    }
}

struct Thumbnail: View {
    let pipeline: ImagePipeline?
    let url: URL
    var pixels = 720
    var fit = false
    @State private var image: RenderedImage?
    @State private var failed = false
    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image {
                    if fit { Image(decorative: image.cgImage, scale: 1).resizable().scaledToFit() }
                    else { Image(decorative: image.cgImage, scale: 1).resizable().scaledToFill() }
                } else {
                    Rectangle().fill(.quaternary).overlay {
                        if failed { Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary) }
                        else { ProgressView() }
                    }
                }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
        .task(id: url) {
            image = nil; failed = false
            do {
                let loaded = try await pipeline?.image(url: url, maxPixel: pixels)
                try Task.checkCancellation(); image = loaded
            } catch { if !Task.isCancelled { failed = true } }
        }
        .onDisappear { image = nil }
    }
}

struct FiltersView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: WallhavenSearchOptions
    @State private var error: String?
    let policy: ContentPolicy
    let hasKey: Bool
    let apply: (WallhavenSearchOptions) -> Void
    init(options: WallhavenSearchOptions, policy: ContentPolicy, hasKey: Bool, apply: @escaping (WallhavenSearchOptions) -> Void) {
        _draft = State(initialValue: options); self.policy = policy; self.hasKey = hasKey; self.apply = apply
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Categorías") { Toggle("General", isOn: $draft.general); Toggle("Anime", isOn: $draft.anime); Toggle("People", isOn: $draft.people) }
                Section {
                    Toggle("SFW", isOn: $draft.sfw)
                    Toggle("Sketchy", isOn: $draft.sketchy).disabled(!policy.sketchy)
                    Toggle("NSFW", isOn: $draft.nsfw).disabled(!policy.nsfw || !hasKey)
                } header: { Text("Contenido") } footer: { Text("El contenido adicional se activa explícitamente en Ajustes. NSFW requiere clave válida.") }
                Section("Ordenación") {
                    Picker("Ordenar por", selection: $draft.sorting) { ForEach(SearchSorting.allCases) { Text($0.title).tag($0) } }
                    Picker("Dirección", selection: $draft.ascending) { Text("Descendente").tag(false); Text("Ascendente").tag(true) }
                    if draft.sorting == .toplist {
                        Picker("Intervalo", selection: $draft.topRange) { ForEach(Array(zip(WallhavenSearchOptions.topRanges, WallhavenSearchOptions.topTitles)), id: \.0) { Text($0.1).tag($0.0) } }
                    }
                }
                Section {
                    TextField("Mínima: 1920x1080", text: $draft.minimumResolution)
                    TextField("Exactas: 1920x1080,2560x1440", text: $draft.resolutions)
                    TextField("Proporciones: 16x9,16x10", text: $draft.ratios)
                } header: { Text("Resolución y proporción") } footer: { Text("Introduce valores personalizados con x. La resolución mínima y las exactas son alternativas.") }
                Section("Color") {
                    Picker("Paleta de Wallhaven", selection: $draft.color) {
                        Text("Cualquier color").tag("")
                        ForEach(WallhavenSearchOptions.palette, id: \.self) { color in Text("#\(color)").tag(color) }
                    }
                }
                Section {
                    TextField("Consulta original", text: $draft.query, axis: .vertical)
                    Text("+etiqueta incluye · -etiqueta excluye · @usuario · id:123 (sin combinar) · type:png o type:jpg · like:abc123").font(.caption).foregroundStyle(.secondary)
                } header: { Text("Consulta avanzada") }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Button("Restablecer") { draft = .init(); error = nil }
            }
            .formStyle(.grouped)
            .navigationTitle("Filtros")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Aplicar") {
                        do { try draft.validate(policy: policy, hasKey: hasKey); apply(draft); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                }
            }
        }
        #if os(macOS)
        .frame(width: 600, height: 720)
        #endif
    }
}
