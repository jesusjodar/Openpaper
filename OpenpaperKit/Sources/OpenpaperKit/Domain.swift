import Foundation

public struct WallpaperIdentity: Codable, Hashable, Sendable {
    public var provider: String
    public var id: String
    public init(provider: String = "wallhaven", id: String) { self.provider = provider; self.id = id }
    public var key: String { "\(provider):\(id)" }
}

public struct Wallpaper: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var provider = "wallhaven"
    public var url: URL
    public var path: URL
    public var thumbnail: URL
    public var width: Int
    public var height: Int
    public var fileSize: Int
    public var fileType: String
    public var purity: String
    public var category: String
    public var colors: [String]
    public var tags: [WallpaperTag]
    public var uploader: String?
    public var source: String?
    public var views: Int
    public var favorites: Int
    public var identity: WallpaperIdentity { .init(provider: provider, id: id) }
    public var resolution: String { "\(width) × \(height)" }
    public var extensionName: String { fileType == "image/png" ? "png" : "jpg" }

    public init(id: String, url: URL, path: URL, thumbnail: URL, width: Int = 0, height: Int = 0,
                fileSize: Int = 0, fileType: String = "image/jpeg", purity: String = "sfw",
                category: String = "general", colors: [String] = [], tags: [WallpaperTag] = [],
                uploader: String? = nil, source: String? = nil, views: Int = 0, favorites: Int = 0) {
        self.id = id; self.url = url; self.path = path; self.thumbnail = thumbnail
        self.width = width; self.height = height; self.fileSize = fileSize; self.fileType = fileType
        self.purity = purity; self.category = category; self.colors = colors; self.tags = tags
        self.uploader = uploader; self.source = source; self.views = views; self.favorites = favorites
    }
}

public struct WallpaperTag: Codable, Hashable, Identifiable, Sendable {
    public var id: Int
    public var name: String
    public var purity: String?
    public init(id: Int, name: String, purity: String? = nil) { self.id = id; self.name = name; self.purity = purity }
}

public struct SearchPage: Sendable {
    public var wallpapers: [Wallpaper]
    public var currentPage: Int
    public var lastPage: Int
    public var total: Int
    public var seed: String?
    public init(wallpapers: [Wallpaper], currentPage: Int, lastPage: Int, total: Int, seed: String? = nil) {
        self.wallpapers = wallpapers; self.currentPage = currentPage; self.lastPage = lastPage; self.total = total; self.seed = seed
    }
}

public struct ProviderCapabilities: Sendable {
    public let categories: Bool
    public let tags: Bool
    public let accountCollections: Bool
    public let remoteWrites: Bool
    public static let wallhaven = ProviderCapabilities(categories: true, tags: true, accountCollections: true, remoteWrites: false)
}

public protocol WallpaperProvider: Sendable {
    var capabilities: ProviderCapabilities { get }
    func search(_ options: WallhavenSearchOptions, page: Int, seed: String?) async throws -> SearchPage
    func detail(id: String) async throws -> Wallpaper
}

public enum SearchSorting: String, Codable, CaseIterable, Identifiable, Sendable {
    case dateAdded = "date_added", relevance, random, views, favorites, toplist, hot
    public var id: String { rawValue }
    var symbol: String {
        switch self { case .dateAdded: "clock"; case .relevance: "sparkle.magnifyingglass"; case .random: "shuffle"; case .views: "eye"; case .favorites: "heart"; case .toplist: "chart.bar"; case .hot: "flame" }
    }
    public var title: String {
        switch self {
        case .dateAdded: "Fecha"
        case .relevance: "Relevancia"
        case .random: "Aleatorio"
        case .views: "Visitas"
        case .favorites: "Favoritos"
        case .toplist: "Populares"
        case .hot: "Tendencias"
        }
    }
}

public struct ContentPolicy: Codable, Equatable, Sendable {
    public var sketchy = false
    public var nsfw = false
    public init(sketchy: Bool = false, nsfw: Bool = false) { self.sketchy = sketchy; self.nsfw = nsfw }
    public func permits(_ wallpaper: Wallpaper) -> Bool {
        switch wallpaper.purity { case "sfw": true; case "sketchy": sketchy; case "nsfw": nsfw; default: false }
    }
}

public struct WallhavenSearchOptions: Codable, Hashable, Sendable {
    public var query = ""
    public var general = true
    public var anime = true
    public var people = true
    public var sfw = true
    public var sketchy = false
    public var nsfw = false
    public var sorting: SearchSorting = .dateAdded
    public var ascending = false
    public var topRange = "1M"
    public var minimumResolution = ""
    public var resolutions = ""
    public var ratios = ""
    public var color = ""
    public init() {}
    public static let topRanges = ["1d", "3d", "1w", "1M", "3M", "6M", "1y"]
    public static let topTitles = ["1 día", "3 días", "Una semana", "Un mes", "3 meses", "6 meses", "Un año"]
    public static let palette = ["660000", "990000", "cc0000", "cc3333", "ea4c88", "993399", "663399", "333399", "0066cc", "0099cc", "66cccc", "77cc33", "669900", "336600", "666600", "999900", "cccc33", "ffff00", "ffcc33", "ff9900", "ff6600", "cc6633", "996633", "663300", "000000", "999999", "cccccc", "ffffff", "424153"]

    public func validate(policy: ContentPolicy, hasKey: Bool) throws {
        guard general || anime || people else { throw OpenpaperError.validation("Selecciona al menos una categoría.") }
        guard sfw || sketchy || nsfw else { throw OpenpaperError.validation("Selecciona al menos un tipo de contenido.") }
        guard !sketchy || policy.sketchy else { throw OpenpaperError.validation("Activa Sketchy en Ajustes antes de buscarlo.") }
        guard !nsfw || (policy.nsfw && hasKey) else { throw OpenpaperError.validation("NSFW requiere activación explícita y una clave API validada.") }
        guard minimumResolution.isEmpty || resolutions.isEmpty else { throw OpenpaperError.validation("Elige resolución mínima o exacta; no pueden combinarse.") }
        for value in [minimumResolution, resolutions, ratios] where !value.isEmpty {
            for part in value.split(separator: ",", omittingEmptySubsequences: false) {
                let numbers = part.split(separator: "x", omittingEmptySubsequences: false)
                guard numbers.count == 2, numbers.allSatisfy({ Int($0).map { $0 > 0 && $0 <= 100_000 } ?? false }) else {
                    throw OpenpaperError.validation("Usa anchoxalto, por ejemplo 1920x1080 o 16x9; separa varios valores con comas.")
                }
            }
        }
        guard !minimumResolution.contains(",") else { throw OpenpaperError.validation("La resolución mínima admite un solo valor.") }
        guard Self.topRanges.contains(topRange) else { throw OpenpaperError.validation("El intervalo de populares no es válido.") }
        guard color.isEmpty || Self.palette.contains(color) else { throw OpenpaperError.validation("Selecciona un color de la paleta de Wallhaven.") }
        let tokens = query.split(whereSeparator: \.isWhitespace)
        if tokens.contains(where: { $0.hasPrefix("id:") }) {
            guard tokens.count == 1, let token = tokens.first, Int(token.dropFirst(3)).map({ $0 > 0 }) == true else {
                throw OpenpaperError.validation("id:123 busca una etiqueta exacta y no puede combinarse con otros términos.")
            }
        }
        for token in tokens where token.hasPrefix("type:") {
            guard ["type:png", "type:jpg"].contains(String(token)) else { throw OpenpaperError.validation("Los formatos admitidos son type:png y type:jpg.") }
        }
        for token in tokens where token.hasPrefix("like:") {
            guard Self.validID(String(token.dropFirst(5))) else { throw OpenpaperError.validation("Usa like: seguido de un ID de seis caracteres.") }
        }
        guard query.count <= 1000 else { throw OpenpaperError.validation("La consulta supera los 1000 caracteres.") }
    }

    public static func validID(_ value: String) -> Bool {
        value.count == 6 && value.utf8.allSatisfy { (48...57).contains($0) || (97...122).contains($0) }
    }

    public func queryItems(page: Int, seed: String?) -> [URLQueryItem] {
        var pairs = [("q", query), ("categories", "\(general ? 1 : 0)\(anime ? 1 : 0)\(people ? 1 : 0)"),
                     ("purity", "\(sfw ? 1 : 0)\(sketchy ? 1 : 0)\(nsfw ? 1 : 0)"),
                     ("sorting", sorting.rawValue), ("order", ascending ? "asc" : "desc"), ("page", String(page))]
        if sorting == .toplist { pairs.append(("topRange", topRange)) }
        if !minimumResolution.isEmpty { pairs.append(("atleast", minimumResolution)) }
        if !resolutions.isEmpty { pairs.append(("resolutions", resolutions)) }
        if !ratios.isEmpty { pairs.append(("ratios", ratios)) }
        if !color.isEmpty { pairs.append(("colors", color)) }
        if sorting == .random, let seed { pairs.append(("seed", seed)) }
        return pairs.map { URLQueryItem(name: $0.0, value: $0.1) }
    }

    public var summary: String {
        let content = [sfw ? "SFW" : nil, sketchy ? "Sketchy" : nil, nsfw ? "NSFW" : nil].compactMap { $0 }.joined(separator: ", ")
        return "\(sorting.title) · \(content)\(minimumResolution.isEmpty ? "" : " · ≥ \(minimumResolution)")\(resolutions.isEmpty ? "" : " · \(resolutions)")\(ratios.isEmpty ? "" : " · \(ratios)")"
    }
}

public enum OpenpaperError: LocalizedError, Equatable, Sendable {
    case validation(String), unauthorized, rateLimited(Int), http(Int), invalidResponse, storage(String), unsupportedProvider
    public var errorDescription: String? {
        switch self {
        case .validation(let text), .storage(let text): text
        case .unauthorized: "La clave API no es válida o no permite acceder a este contenido. Revísala en Ajustes."
        case .rateLimited(let seconds): "Wallhaven limita las peticiones. Reintenta dentro de \(seconds) segundos."
        case .http(let code): "El servidor ha respondido con el error \(code). Puedes reintentar."
        case .invalidResponse: "La respuesta del proveedor no es válida."
        case .unsupportedProvider: "Este proveedor todavía no está disponible."
        }
    }
}

public struct RemoteCollection: Codable, Identifiable, Sendable {
    public var id: Int
    public var label: String
    public var count: Int
}

public struct AccountPreferences: Codable, Sendable {
    public var purity: [String]?
    public var categories: [String]?
    public var resolutions: [String]?
    public var aspect_ratios: [String]?
    public var toplist_range: String?
    public var tag_blacklist: [String]?
    public var user_blacklist: [String]?
}

public struct RotationOrder: Sendable {
    private var remaining: [String] = []
    private var source: Set<String> = []
    public init() {}
    public mutating func next(ids: [String], random: Bool) -> String? {
        let unique = Array(NSOrderedSet(array: ids)) as? [String] ?? []
        guard !unique.isEmpty else { return nil }
        if source != Set(unique) || remaining.isEmpty {
            source = Set(unique); remaining = random ? unique.shuffled() : unique
        }
        return remaining.removeFirst()
    }
}

public struct CropGeometry: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(imageWidth: Double, imageHeight: Double, aspect: Double, zoom: Double, offsetX: Double, offsetY: Double) {
        let safeAspect = max(0.01, aspect)
        width = min(imageWidth, imageHeight * safeAspect) / max(1, zoom)
        height = width / safeAspect
        x = min(max(0, (imageWidth - width) / 2 - offsetX * width), imageWidth - width)
        y = min(max(0, (imageHeight - height) / 2 - offsetY * height), imageHeight - height)
    }
}
