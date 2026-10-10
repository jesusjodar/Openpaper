import SwiftUI
import UniformTypeIdentifiers

struct TransferDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, data.count <= 50_000_000 else { throw OpenpaperError.invalidResponse }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct ImageDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.jpeg, .png] }
    var data: Data
    var type: UTType
    init(file: URL) throws { data = try Data(contentsOf: file); type = file.pathExtension.lowercased() == "png" ? .png : .jpeg }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw OpenpaperError.invalidResponse }
        self.data = data; type = configuration.contentType
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct LibraryView: View {
    @Bindable var session: AppSession
    @State private var section = "favorites"
    @State private var selecting = false
    @State private var selection: Set<String> = []
    @State private var collectionName = ""
    @State private var naming = false
    @State private var renaming = false
    @State private var deleteCollection = false
    @State private var deleteSearch: SavedSearch?
    @State private var importing = false
    @State private var exporting = false
    @State private var document = TransferDocument()
    @State private var remote = false
    private var library: LibraryStore? { session.library }
    private var collection: LocalCollection? { library?.collections.first { $0.id.uuidString == section } }
    private var wallpapers: [Wallpaper] {
        let records = library?.items ?? []
        let filtered: [LibraryItem]
        if let collection { filtered = records.filter { collection.keys.contains($0.key) } }
        else if section == "downloads" { filtered = records.filter { $0.wallpaper.flatMap { library?.localURL($0) } != nil } }
        else { filtered = records.filter(\.favorite) }
        return filtered.compactMap(\.wallpaper).filter { session.policy.permits($0) }
    }
    private var selectedWallpapers: [Wallpaper] { wallpapers.filter { selection.contains($0.identity.key) } }
    var body: some View {
        VStack(spacing: 0) {
            Picker("Mostrar", selection: $section) {
                Text("Favoritos").tag("favorites")
                Text("Descargas").tag("downloads")
                Text("Búsquedas guardadas").tag("searches")
                if let library { ForEach(library.collections) { Text($0.name).tag($0.id.uuidString) } }
            }.padding()
            if section == "searches" {
                if let library, !library.searches.isEmpty {
                    List { ForEach(library.searches) { search in
                        HStack {
                            Button { if let options = search.options { session.useSearch(options) } } label: { Label(search.name, systemImage: "bookmark") }
                            Spacer()
                            Button("Eliminar búsqueda", systemImage: "trash", role: .destructive) { deleteSearch = search }.labelStyle(.iconOnly)
                        }
                    } }
                } else { ContentUnavailableView("Sin búsquedas guardadas", systemImage: "bookmark", description: Text("Guarda una búsqueda desde Buscar para volver a sus filtros o usarla en la rotación.")) }
            } else if wallpapers.isEmpty {
                ContentUnavailableView("Tu biblioteca empieza aquí", systemImage: "photo.stack", description: Text("Añade favoritos, descarga originales o reúne fondos en una colección. Los metadatos guardados estarán disponibles sin conexión."))
            } else {
                if selecting {
                    HStack {
                        Text("\(selection.count) seleccionados").font(.caption)
                        Spacer()
                        Button("Seleccionar todos") { selection = Set(wallpapers.map { $0.identity.key }) }
                        Menu("Añadir a colección") {
                            if let library { ForEach(library.collections) { collection in
                                Button(collection.name) { session.perform { try library.add(selectedWallpapers, to: collection) } }
                            } }
                        }.disabled(selection.isEmpty || library?.collections.isEmpty == true)
                        Button("Descargar", systemImage: "arrow.down") { downloadSelection() }.disabled(selection.isEmpty)
                        if let collection {
                            Button("Quitar", systemImage: "minus.circle") { session.perform { try library?.remove(keys: selection, from: collection); selection = [] } }.disabled(selection.isEmpty)
                        }
                    }.padding(.horizontal)
                }
                ScrollView { WallpaperGrid(session: session, wallpapers: wallpapers, selecting: selecting, selection: $selection) }
            }
        }
        .navigationTitle("Biblioteca")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(selecting ? "Hecho" : "Seleccionar", systemImage: selecting ? "checkmark" : "checkmark.circle") { selecting.toggle(); selection = [] }.disabled(wallpapers.isEmpty)
                Menu("Biblioteca", systemImage: "ellipsis.circle") {
                    Button("Crear colección", systemImage: "folder.badge.plus") { collectionName = ""; renaming = false; naming = true }
                    if let collection {
                        Button("Renombrar colección") { collectionName = collection.name; renaming = true; naming = true }
                        Button("Eliminar colección", role: .destructive) { deleteCollection = true }
                    }
                    Divider()
                    Button("Colecciones de Wallhaven", systemImage: "network") { remote = true }
                    Button("Exportar biblioteca", systemImage: "square.and.arrow.up") {
                        session.perform { document = TransferDocument(data: try library?.exportData() ?? Data()); exporting = true }
                    }
                    Button("Importar biblioteca", systemImage: "square.and.arrow.down") { importing = true }
                }
            }
        }
        .onChange(of: section) { selection = []; selecting = false }
        .alert(renaming ? "Renombrar colección" : "Crear colección", isPresented: $naming) {
            TextField("Nombre", text: $collectionName)
            Button("Guardar") { session.perform {
                if renaming, let collection { try library?.rename(collection, name: collectionName) }
                else { try library?.createCollection(name: collectionName) }
            } }
            Button("Cancelar", role: .cancel) {}
        }
        .confirmationDialog("¿Eliminar esta colección? Los favoritos y originales se conservarán.", isPresented: $deleteCollection, titleVisibility: .visible) {
            Button("Eliminar colección", role: .destructive) { if let collection { session.perform { try library?.delete(collection); section = "favorites" } } }
        }
        .confirmationDialog("¿Eliminar esta búsqueda guardada?", isPresented: Binding(get: { deleteSearch != nil }, set: { if !$0 { deleteSearch = nil } }), titleVisibility: .visible) {
            Button("Eliminar búsqueda", role: .destructive) { if let search = deleteSearch { session.perform { try library?.delete(search) }; deleteSearch = nil } }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "Openpaper-biblioteca") { result in
            if case .failure(let error) = result { session.message = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result { case .success(let url): importFile(url); case .failure(let error): session.message = error.localizedDescription }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard urls.count == 1, let url = urls.first, url.pathExtension.lowercased() == "json" else { return false }
            importFile(url); return true
        }
        .sheet(isPresented: $remote) { RemoteCollectionsView(session: session) }
    }
    private func importFile(_ url: URL) {
        Task {
            do {
                let data = try await Task.detached {
                    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 50_000_000 else { throw OpenpaperError.validation("El archivo supera los 50 MB.") }
                    return try Data(contentsOf: url)
                }.value
                try library?.importData(data); session.notice = "Biblioteca combinada. Los datos existentes se conservan."
            } catch { session.message = error.localizedDescription }
        }
    }
    private func downloadSelection() {
        let selected = selectedWallpapers
        Task {
            await withTaskGroup(of: String?.self) { group in
                for wallpaper in selected {
                    group.addTask { do { _ = try await session.download(wallpaper); return nil } catch { return error.localizedDescription } }
                }
                var failures: [String] = []
                for await error in group { if let error { failures.append(error) } }
                if let first = failures.first { session.message = "\(failures.count) descargas fallaron. \(first)" }
            }
        }
    }
}

struct RemoteCollectionsView: View {
    var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var username: String
    @State private var own = false
    @State private var collections: [RemoteCollection] = []
    @State private var loading = false
    @State private var error: String?
    init(session: AppSession, username: String = "") { self.session = session; _username = State(initialValue: username) }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Usuario propietario", text: $username)
                    Toggle("Mis colecciones (requiere clave)", isOn: $own).disabled(!session.keyValidated)
                    Button("Cargar colecciones") { Task { await load() } }.disabled(loading || username.isEmpty)
                    if loading { ProgressView("Cargando…") }
                    if let error { Text(error).foregroundStyle(.red) }
                } header: { Text("Colecciones remotas") } footer: { Text("Indica también tu nombre de usuario para abrir tus colecciones. Las colecciones remotas solo admiten el filtro de contenido y no se modifican desde Openpaper.") }
                ForEach(collections) { collection in
                    NavigationLink { RemoteCollectionResults(session: session, username: username, collection: collection) } label: {
                        HStack { Text(collection.label); Spacer(); Text("\(collection.count)").foregroundStyle(.secondary) }
                    }
                }
                Link("Gestionar en Wallhaven ↗", destination: URL(string: "https://wallhaven.cc")!)
            }
            .navigationTitle("Wallhaven")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
            .navigationDestination(for: Wallpaper.self) { DetailView(session: session, wallpaper: $0) }
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 680)
        #endif
    }
    private func load() async {
        loading = true; error = nil; collections = []
        defer { loading = false }
        do { collections = try await session.client.collections(username: own ? nil : username) }
        catch { self.error = error.localizedDescription }
    }
}

private struct RemoteCollectionResults: View {
    var session: AppSession
    let username: String
    let collection: RemoteCollection
    @State private var feed = SearchFeed()
    var body: some View {
        SearchResultsView(session: session, feed: feed).navigationTitle(collection.label)
            .task {
                guard feed.currentPage == 0 else { return }
                feed.remote = (username, collection.id)
                await feed.refresh(client: session.client)
            }
    }
}
