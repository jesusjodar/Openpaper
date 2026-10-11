import SwiftUI
import UniformTypeIdentifiers

public struct OpenpaperRoot: View {
    var session: AppSession
    @Environment(\.scenePhase) private var phase
    public init(session: AppSession) { self.session = session }
    public var body: some View {
        #if os(macOS)
        NativeGlassContainer { OpenpaperContent(session: session).environment(\.scenePhase, phase) }
        #else
        OpenpaperContent(session: session)
        #endif
    }
}

private struct OpenpaperContent: View {
    @Bindable var session: AppSession
    @Environment(\.scenePhase) private var scenePhase
    @State private var settings = false
    var body: some View {
        GlassEffectContainer(spacing: 0) {
        Group {
            if let error = session.startupError {
                ContentUnavailableView("No se pudo abrir la biblioteca", systemImage: "externaldrive.badge.exclamationmark", description: Text("\(error)\nLos archivos existentes se conservan. Cierra la app y revisa el espacio o los permisos antes de reabrirla."))
            } else {
                TabView(selection: $session.destination) {
                    ForEach(Destination.allCases) { destination in
                        Tab(destination.rawValue, systemImage: destination.symbol, value: destination) {
                            DestinationStack(session: session, destination: destination, settings: $settings)
                        }
                    }
                }
                #if os(macOS)
                .tabViewStyle(.tabBarOnly)
                .defaultTabBarPlacement(.tabBar)
                #else
                .tabViewStyle(.tabBarOnly)
                .defaultAdaptableTabBarPlacement(.tabBar)
                #endif

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
    }
}

private struct DestinationStack: View {
    var session: AppSession
    let destination: Destination
    @Binding var settings: Bool
    @State private var path: [Wallpaper] = []
    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch destination {
                case .explore: DiscoveryView(session: session, feed: session.explore, isSearch: false)
                case .search: DiscoveryView(session: session, feed: session.search, isSearch: true)
                case .library: LibraryView(session: session)
                }
            }
            .navigationDestination(for: Wallpaper.self) { DetailView(session: session, wallpaper: $0) }
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) { Button("Ajustes", systemImage: "gearshape") { settings = true } }
                #endif
            }
        }
        .onChange(of: session.search.options.query) { if destination == .search { path.removeAll() } }
    }
}

struct DiscoveryView: View {
    @Bindable var session: AppSession
    @Bindable var feed: SearchFeed
    var isSearch: Bool
    @State private var filters = false
    @State private var savingSearch = false
    @State private var searchName = ""
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var sorts: [SearchSorting] { isSearch ? SearchSorting.allCases : [.dateAdded, .toplist, .hot, .random] }
    private struct RefreshKey: Hashable { var options: WallhavenSearchOptions; var active: Bool }
    var body: some View {
        Group {
            #if os(macOS)
            sortingTabs.tabViewStyle(.grouped)
            #else
            if sizeClass == .compact {
                VStack(spacing: 0) {
                    ViewThatFits(in: .horizontal) {
                        Picker("Ordenar por", selection: $feed.options.sorting) { ForEach(sorts) { Text($0.title).tag($0) } }.pickerStyle(.segmented).fixedSize()
                        Picker("Ordenar por", selection: $feed.options.sorting) { ForEach(sorts) { Text($0.title).tag($0) } }.pickerStyle(.menu).buttonStyle(.glass)
                    }.padding(.horizontal).padding(.vertical, 8)
                    results
                }
            } else { sortingTabs.tabViewStyle(.tabBarOnly) }
            #endif
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
        .task(id: RefreshKey(options: feed.options, active: session.destination == (isSearch ? .search : .explore))) {
            guard session.destination == (isSearch ? .search : .explore), feed.needsRefresh else { return }
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
    private var sortingTabs: some View {
        TabView(selection: $feed.options.sorting) {
            ForEach(sorts) { sort in
                Tab(sort.title, systemImage: sort.symbol, value: sort) {
                    if feed.options.sorting == sort { results }
                }
            }
        }
    }
    private var results: some View {
        VStack(spacing: 0) {
            FilterBar(options: feed.options, remote: feed.remote != nil) { filters = true }
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
                MasonryScroll(session: session, wallpapers: feed.results) {
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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 88))], spacing: 8) {
                        GlassPill(title: "Cualquiera", selected: draft.color.isEmpty) { draft.color = "" }
                        ForEach(WallhavenSearchOptions.palette, id: \.self) { color in
                            GlassPill(title: "#" + color, selected: draft.color == color, tint: Color(hex: color)) { draft.color = color }
                                .accessibilityLabel("Color #\(color)\(draft.color == color ? ", seleccionado" : "")")
                        }
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

struct FilterBar: View {
    let options: WallhavenSearchOptions
    var remote = false
    var edit: () -> Void
    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 8) {
                    if !remote {
                        GlassPill(title: "Categorías", selected: !(options.general && options.anime && options.people), action: edit)
                    }
                    GlassPill(title: options.sfw && !options.sketchy && !options.nsfw ? "SFW" : "Contenido", selected: true, action: edit)
                    if !remote {
                        GlassPill(title: "Resolución", selected: !options.minimumResolution.isEmpty || !options.resolutions.isEmpty, action: edit)
                        GlassPill(title: "Proporción", selected: !options.ratios.isEmpty, action: edit)
                        GlassPill(title: options.color.isEmpty ? "Color" : "#" + options.color, selected: !options.color.isEmpty, tint: options.color.isEmpty ? nil : Color(hex: options.color), action: edit)
                        GlassPill(title: "Más filtros", selected: options.ascending || options.topRange != "1M", action: edit)
                    }
                }.padding(.horizontal, 16).padding(.vertical, 8)
            }
        }.scrollIndicators(.hidden).fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel("Filtros aplicados: \(options.summary)")
    }
}
