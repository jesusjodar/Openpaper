import AppIntents
import Foundation

private struct ShortcutContext {
    let session: AppSession
    let library: LibraryStore
    let client: WallhavenClient
    let downloads: DownloadService
    let policy: ContentPolicy

    @MainActor static func make(session: AppSession) async throws -> ShortcutContext {
        try await session.prepareServices()
        guard let library = session.library, let downloads = session.downloads else { throw OpenpaperError.storage("La biblioteca no está disponible.") }
        return .init(session: session, library: library, client: session.client, downloads: downloads, policy: session.policy)
    }
    @MainActor func file(_ wallpaper: Wallpaper) async throws -> IntentFile {
        guard policy.permits(wallpaper) else { throw OpenpaperError.validation("Este fondo no cumple el contenido permitido en Openpaper.") }
        let url = try await session.download(wallpaper)
        return IntentFile(fileURL: url, filename: url.lastPathComponent, type: wallpaper.extensionName == "png" ? .png : .jpeg)
    }
}

public struct OpenpaperCollectionEntity: AppEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Colección de Openpaper")
    public static let defaultQuery = OpenpaperCollectionQuery()
    public let id: UUID
    public let name: String
    public var displayRepresentation: DisplayRepresentation { .init(title: "\(name)") }
}

public struct OpenpaperCollectionQuery: EntityStringQuery {
    @Dependency private var session: AppSession
    public init() {}
    @MainActor public func entities(for identifiers: [UUID]) async throws -> [OpenpaperCollectionEntity] {
        (session.library?.collections ?? []).filter { identifiers.contains($0.id) }.map { .init(id: $0.id, name: $0.name) }
    }
    @MainActor public func entities(matching string: String) async throws -> [OpenpaperCollectionEntity] {
        (session.library?.collections ?? []).filter { $0.name.localizedCaseInsensitiveContains(string) }.map { .init(id: $0.id, name: $0.name) }
    }
    @MainActor public func suggestedEntities() async throws -> [OpenpaperCollectionEntity] {
        (session.library?.collections ?? []).map { .init(id: $0.id, name: $0.name) }
    }
}

public struct RandomWallpaperIntent: AppIntent {
    @Dependency private var session: AppSession
    public static let title: LocalizedStringResource = "Obtener un fondo aleatorio"
    public static let description = IntentDescription("Descarga una imagen aleatoria usando tus filtros y el contenido permitido en Openpaper.")
    public init() {}
    @MainActor public func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let context = try await ShortcutContext.make(session: session)
        var options = UserDefaults.standard.data(forKey: "preferences-v1").flatMap { try? JSONDecoder().decode(AppPreferences.self, from: $0) }?.defaultOptions ?? .init()
        options.sorting = .random
        let results = try await context.client.search(options, page: 1, seed: nil)
        guard let wallpaper = results.wallpapers.first else { throw OpenpaperError.validation("La búsqueda no contiene fondos disponibles.") }
        return .result(value: try await context.file(wallpaper))
    }
}

public struct CollectionWallpaperIntent: AppIntent {
    @Dependency private var session: AppSession
    public static let title: LocalizedStringResource = "Obtener un fondo de una colección"
    public static let description = IntentDescription("Entrega una imagen aleatoria de una colección local. Usa una descarga existente cuando está disponible.")
    @Parameter(title: "Colección") public var collection: OpenpaperCollectionEntity
    public init() {}
    @MainActor public func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let context = try await ShortcutContext.make(session: session)
        guard let collection = context.library.collections.first(where: { $0.id == self.collection.id }) else { throw OpenpaperError.validation("La colección ya no existe.") }
        let wallpapers = context.library.items.filter { collection.keys.contains($0.key) }.compactMap(\.wallpaper).filter { context.policy.permits($0) }
        guard let wallpaper = wallpapers.randomElement() else { throw OpenpaperError.validation("La colección no contiene fondos con el contenido permitido.") }
        return .result(value: try await context.file(wallpaper))
    }
}

public struct DownloadWallpaperIntent: AppIntent {
    @Dependency private var session: AppSession
    public static let title: LocalizedStringResource = "Descargar un fondo"
    public static let description = IntentDescription("Descarga el original de Wallhaven a partir de su ID de seis caracteres.")
    @Parameter(title: "ID de Wallhaven") public var wallpaperID: String
    public init() {}
    @MainActor public func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let context = try await ShortcutContext.make(session: session)
        let wallpaper = try await context.client.detail(id: wallpaperID)
        return .result(value: try await context.file(wallpaper))
    }
}

#if os(macOS)
public struct ApplyWallpaperIntent: AppIntent {
    @Dependency private var session: AppSession
    public static let title: LocalizedStringResource = "Aplicar un fondo en Mac"
    public static let description = IntentDescription("Descarga y aplica un fondo de Wallhaven a todos los monitores conectados.")
    @Parameter(title: "ID de Wallhaven") public var wallpaperID: String
    public init() {}
    @MainActor public func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let context = try await ShortcutContext.make(session: session)
        let wallpaper = try await context.client.detail(id: wallpaperID)
        let file = try await context.file(wallpaper)
        guard let url = context.library.localURL(wallpaper) else { throw OpenpaperError.invalidResponse }
        try session.application.apply(file: url, target: nil, fill: true)
        return .result(value: file)
    }
}
#endif

public struct OpenpaperShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RandomWallpaperIntent(), phrases: ["Obtén un fondo aleatorio con \(.applicationName)"], shortTitle: "Fondo aleatorio", systemImageName: "shuffle")
        AppShortcut(intent: CollectionWallpaperIntent(), phrases: ["Obtén un fondo de una colección con \(.applicationName)"], shortTitle: "Fondo de colección", systemImageName: "photo.stack")
        AppShortcut(intent: DownloadWallpaperIntent(), phrases: ["Descarga un fondo con \(.applicationName)"], shortTitle: "Descargar fondo", systemImageName: "arrow.down.circle")
        #if os(macOS)
        AppShortcut(intent: ApplyWallpaperIntent(), phrases: ["Aplica un fondo con \(.applicationName)"], shortTitle: "Aplicar fondo", systemImageName: "desktopcomputer")
        #endif
    }
}
