import Foundation
import SwiftData
import Observation
import Security

@Model public final class LibraryItem {
    @Attribute(.unique) public var key: String
    public var metadata: Data
    public var favorite: Bool
    public var fileName: String?
    public var createdAt: Date
    public init(wallpaper: Wallpaper, favorite: Bool = false) throws {
        key = wallpaper.identity.key; metadata = try JSONEncoder().encode(wallpaper)
        self.favorite = favorite; createdAt = .now
    }
    public var wallpaper: Wallpaper? { try? JSONDecoder().decode(Wallpaper.self, from: metadata) }
}

@Model public final class LocalCollection {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var keys: [String]
    public var createdAt: Date
    public init(id: UUID = UUID(), name: String, keys: [String] = []) {
        self.id = id; self.name = name; self.keys = keys; createdAt = .now
    }
}

@Model public final class SavedSearch {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var optionsData: Data
    public var cachedKeys: [String] = []
    public init(id: UUID = UUID(), name: String, options: WallhavenSearchOptions) throws {
        self.id = id; self.name = name; optionsData = try JSONEncoder().encode(options)
    }
    public var options: WallhavenSearchOptions? { try? JSONDecoder().decode(WallhavenSearchOptions.self, from: optionsData) }
}

public enum LibrarySchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { .init(1, 0, 0) }
    public static var models: [any PersistentModel.Type] { [LibraryItem.self, LocalCollection.self, SavedSearch.self] }
}
public enum LibraryMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [LibrarySchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}

public struct LibraryTransfer: Codable, Sendable {
    public var version = 1
    public var wallpapers: [Entry]
    public var collections: [Collection]
    public var searches: [Search]
    public struct Entry: Codable, Sendable { public var wallpaper: Wallpaper; public var favorite: Bool }
    public struct Collection: Codable, Sendable { public var id: UUID; public var name: String; public var keys: [String] }
    public struct Search: Codable, Sendable { public var id: UUID; public var name: String; public var options: WallhavenSearchOptions }
    public init(wallpapers: [Entry] = [], collections: [Collection] = [], searches: [Search] = []) {
        self.wallpapers = wallpapers; self.collections = collections; self.searches = searches
    }
    public func validate() throws {
        guard version == 1 else { throw OpenpaperError.validation("Este formato de transferencia no es compatible (versión \(version)).") }
        guard wallpapers.count <= 20_000, collections.count <= 2000, searches.count <= 2000 else { throw OpenpaperError.validation("El archivo contiene demasiados elementos.") }
        var identities = Set<String>()
        for entry in wallpapers {
            let w = entry.wallpaper
            guard w.provider == "wallhaven", WallhavenSearchOptions.validID(w.id), MediaURLs.isTrusted(w.path),
                  MediaURLs.isTrusted(w.thumbnail), w.url.scheme == "https", ["wallhaven.cc", "www.whvn.cc"].contains(w.url.host ?? ""),
                  w.url.path == "/w/\(w.id)", w.url.query == nil, w.url.user == nil, w.url.password == nil,
                  ["sfw", "sketchy", "nsfw"].contains(w.purity), w.width >= 0, w.height >= 0, w.fileSize >= 0,
                  ["image/jpeg", "image/png"].contains(w.fileType) else { throw OpenpaperError.invalidResponse }
            if let source = w.source, !source.isEmpty {
                guard let url = URL(string: source), ["http", "https"].contains(url.scheme ?? ""), url.user == nil, url.password == nil else { throw OpenpaperError.invalidResponse }
            }
            guard identities.insert(w.identity.key).inserted else { throw OpenpaperError.validation("El archivo repite la identidad de un fondo.") }
        }
        guard Set(collections.map(\.id)).count == collections.count, Set(searches.map(\.id)).count == searches.count else { throw OpenpaperError.validation("El archivo repite colecciones o búsquedas.") }
        for collection in collections {
            try Self.validateName(collection.name)
            guard collection.keys.count <= 20_000, collection.keys.allSatisfy({ identities.contains($0) }) else { throw OpenpaperError.validation("Una colección contiene referencias a fondos ausentes.") }
        }
        for search in searches {
            try Self.validateName(search.name)
            try search.options.validate(policy: .init(sketchy: true, nsfw: true), hasKey: true)
        }
    }
    static func validateName(_ name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 100 else { throw OpenpaperError.validation("El nombre debe tener entre 1 y 100 caracteres.") }
    }
}

@MainActor @Observable public final class LibraryStore {
    public let container: ModelContainer
    private let context: ModelContext
    public private(set) var items: [LibraryItem] = []
    public private(set) var collections: [LocalCollection] = []
    public private(set) var searches: [SavedSearch] = []
    public let root: URL

    public init(inMemory: Bool = false, root: URL? = nil) throws {
        self.root = try root ?? Self.applicationDirectory()
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        let schema = Schema(versionedSchema: LibrarySchemaV1.self)
        let config = inMemory ? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true) : ModelConfiguration(schema: schema, url: self.root.appendingPathComponent("Library.store"), cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: config)
        context = ModelContext(container); context.autosaveEnabled = false
        try refresh()
    }
    public static func applicationDirectory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Openpaper", isDirectory: true)
    }
    private func refresh() throws {
        items = try context.fetch(FetchDescriptor<LibraryItem>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
        collections = try context.fetch(FetchDescriptor<LocalCollection>(sortBy: [SortDescriptor(\.createdAt)]))
        searches = try context.fetch(FetchDescriptor<SavedSearch>(sortBy: [SortDescriptor(\.name)]))
    }
    private func commit(_ action: () throws -> Void) throws {
        do { try action(); try context.save(); try refresh() }
        catch { context.rollback(); try? refresh(); throw error }
    }
    public func item(_ wallpaper: Wallpaper) -> LibraryItem? { items.first { $0.key == wallpaper.identity.key } }
    public func localURL(_ wallpaper: Wallpaper) -> URL? {
        guard let name = item(wallpaper)?.fileName, name == URL(fileURLWithPath: name).lastPathComponent else { return nil }
        let file = root.appendingPathComponent("Originals", isDirectory: true).appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }
    @discardableResult private func upsert(_ wallpaper: Wallpaper) throws -> LibraryItem {
        if let found = item(wallpaper) { found.metadata = try JSONEncoder().encode(wallpaper); return found }
        let record = try LibraryItem(wallpaper: wallpaper); context.insert(record); return record
    }
    public func toggleFavorite(_ wallpaper: Wallpaper) throws {
        try commit { let record = try upsert(wallpaper); record.favorite.toggle() }
    }
    public func markDownloaded(_ wallpaper: Wallpaper, fileName: String) throws {
        guard fileName == URL(fileURLWithPath: fileName).lastPathComponent else { throw OpenpaperError.invalidResponse }
        try commit { try upsert(wallpaper).fileName = fileName }
    }
    public func createCollection(name: String) throws {
        try LibraryTransfer.validateName(name)
        try commit { context.insert(LocalCollection(name: name.trimmingCharacters(in: .whitespacesAndNewlines))) }
    }
    public func rename(_ collection: LocalCollection, name: String) throws {
        try LibraryTransfer.validateName(name)
        try commit { collection.name = name.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    public func delete(_ collection: LocalCollection) throws { try commit { context.delete(collection) } }
    public func add(_ wallpapers: [Wallpaper], to collection: LocalCollection) throws {
        try commit {
            for wallpaper in wallpapers {
                _ = try upsert(wallpaper)
                if !collection.keys.contains(wallpaper.identity.key) { collection.keys.append(wallpaper.identity.key) }
            }
        }
    }
    public func remove(keys: Set<String>, from collection: LocalCollection) throws { try commit { collection.keys.removeAll { keys.contains($0) } } }
    public func saveSearch(name: String, options: WallhavenSearchOptions) throws {
        try LibraryTransfer.validateName(name)
        try options.validate(policy: .init(sketchy: true, nsfw: true), hasKey: true)
        try commit { context.insert(try SavedSearch(name: name, options: options)) }
    }
    public func delete(_ search: SavedSearch) throws { try commit { context.delete(search) } }
    public func cache(_ wallpapers: [Wallpaper], for search: SavedSearch) throws {
        try commit {
            for wallpaper in wallpapers {
                _ = try upsert(wallpaper)
                if !search.cachedKeys.contains(wallpaper.identity.key) { search.cachedKeys.append(wallpaper.identity.key) }
            }
        }
    }
    public func exportData() throws -> Data {
        let referenced = Set(collections.flatMap(\.keys))
        let entries = items.filter { $0.favorite || referenced.contains($0.key) }.compactMap { item -> LibraryTransfer.Entry? in
            guard let wallpaper = item.wallpaper else { return nil }; return .init(wallpaper: wallpaper, favorite: item.favorite)
        }
        let transfer = LibraryTransfer(wallpapers: entries, collections: collections.map { .init(id: $0.id, name: $0.name, keys: $0.keys) },
                                      searches: searches.compactMap { search in search.options.map { .init(id: search.id, name: search.name, options: $0) } })
        try transfer.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(transfer)
    }
    public func importData(_ data: Data) throws {
        guard data.count <= 50_000_000 else { throw OpenpaperError.validation("El archivo supera los 50 MB.") }
        let transfer = try JSONDecoder().decode(LibraryTransfer.self, from: data)
        try transfer.validate()
        try commit {
            for entry in transfer.wallpapers {
                if let found = items.first(where: { $0.key == entry.wallpaper.identity.key }) { found.favorite = found.favorite || entry.favorite }
                else { context.insert(try LibraryItem(wallpaper: entry.wallpaper, favorite: entry.favorite)) }
            }
            for collection in transfer.collections {
                if let found = collections.first(where: { $0.id == collection.id }) {
                    found.keys += collection.keys.filter { !found.keys.contains($0) }
                } else { context.insert(LocalCollection(id: collection.id, name: collection.name, keys: Array(Set(collection.keys)).sorted())) }
            }
            for search in transfer.searches where !searches.contains(where: { $0.id == search.id }) {
                context.insert(try SavedSearch(id: search.id, name: search.name, options: search.options))
            }
        }
    }
}

enum KeychainStore {
    private static let service = "com.jesusjodar.openpaper.wallhaven"
    static func read() throws -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "api-key", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else { throw OpenpaperError.storage("No se pudo leer la clave del Llavero (\(status)).") }
        return key
    }
    static func write(_ value: String?) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "api-key"]
        if let value {
            let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if status == errSecItemNotFound {
                let added = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
                guard added == errSecSuccess else { throw OpenpaperError.storage("No se pudo guardar la clave en el Llavero (\(added)).") }
            } else if status != errSecSuccess { throw OpenpaperError.storage("No se pudo actualizar la clave del Llavero (\(status)).") }
        } else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw OpenpaperError.storage("No se pudo eliminar la clave del Llavero (\(status)).") }
        }
    }
}
