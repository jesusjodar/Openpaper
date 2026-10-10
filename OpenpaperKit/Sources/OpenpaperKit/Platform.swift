import Foundation
#if os(macOS)
import AppKit
#else
import Photos
import UIKit
#endif

public struct ScreenTarget: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var width: Int
    public var height: Int
    public var aspect: Double { Double(width) / Double(max(1, height)) }
}

@MainActor public protocol WallpaperApplicationService {
    var screens: [ScreenTarget] { get }
    func apply(file: URL, target: String?, fill: Bool) throws
    func restorePrevious() throws
}

#if os(macOS)
@MainActor public final class MacWallpaperService: WallpaperApplicationService {
    private struct Previous: Codable { var id: String; var url: URL; var fill: Bool; var scaling: Int? }
    private var previous: [Previous]
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        previous = defaults.data(forKey: "previous-desktop").flatMap { try? JSONDecoder().decode([Previous].self, from: $0) } ?? []
    }
    private func id(_ screen: NSScreen) -> String { String((screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0) }
    public var screens: [ScreenTarget] {
        NSScreen.screens.map { screen in
            ScreenTarget(id: id(screen), name: screen.localizedName,
                         width: Int(screen.frame.width * screen.backingScaleFactor), height: Int(screen.frame.height * screen.backingScaleFactor))
        }
    }
    public func apply(file: URL, target: String?, fill: Bool) throws {
        guard file.isFileURL, FileManager.default.fileExists(atPath: file.path) else { throw OpenpaperError.storage("El archivo del fondo ya no está disponible.") }
        let screens = NSScreen.screens.filter { target == nil || id($0) == target }
        guard !screens.isEmpty else { throw OpenpaperError.validation("El monitor elegido no está conectado.") }
        let snapshots = screens.compactMap { screen -> Previous? in
            guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
            let options = NSWorkspace.shared.desktopImageOptions(for: screen)
            return Previous(id: id(screen), url: url, fill: options?[.allowClipping] as? Bool ?? true, scaling: options?[.imageScaling] as? Int)
        }
        previous = snapshots
        defaults.set(try JSONEncoder().encode(previous), forKey: "previous-desktop")
        var applied: [NSScreen] = []
        do {
            for screen in screens {
                try NSWorkspace.shared.setDesktopImageURL(file, for: screen, options: [.imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue, .allowClipping: fill])
                applied.append(screen)
            }
        } catch {
            for screen in applied {
                if let saved = snapshots.first(where: { $0.id == id(screen) }) {
                    try? NSWorkspace.shared.setDesktopImageURL(saved.url, for: screen, options: [.allowClipping: saved.fill, .imageScaling: saved.scaling ?? NSImageScaling.scaleProportionallyUpOrDown.rawValue])
                }
            }
            throw error
        }
    }
    public func restorePrevious() throws {
        guard !previous.isEmpty else { throw OpenpaperError.validation("No hay un fondo anterior guardado.") }
        let targets = try previous.map { saved -> (Previous, NSScreen) in
            guard FileManager.default.fileExists(atPath: saved.url.path) else { throw OpenpaperError.storage("El fondo anterior ya no está disponible.") }
            guard let screen = NSScreen.screens.first(where: { id($0) == saved.id }) else { throw OpenpaperError.validation("Un monitor del fondo anterior está desconectado.") }
            return (saved, screen)
        }
        for (saved, screen) in targets {
            try NSWorkspace.shared.setDesktopImageURL(saved.url, for: screen, options: [.allowClipping: saved.fill, .imageScaling: saved.scaling ?? NSImageScaling.scaleProportionallyUpOrDown.rawValue])
        }
    }
    public func isApplied(_ url: URL) -> Bool { NSScreen.screens.contains { NSWorkspace.shared.desktopImageURL(for: $0)?.standardizedFileURL == url.standardizedFileURL } }
}
#else
@MainActor public enum MobileScreenService {
    public static var target: ScreenTarget? {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return nil }
        let bounds = scene.screen.nativeBounds
        let landscape = scene.effectiveGeometry.interfaceOrientation.isLandscape
        return ScreenTarget(id: "mobile", name: "Esta pantalla", width: Int(landscape ? bounds.height : bounds.width), height: Int(landscape ? bounds.width : bounds.height))
    }
}
public enum PhotosService {
    public static func save(_ file: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw OpenpaperError.validation("Fotos no permite añadir imágenes. Puedes habilitarlo en Ajustes del sistema o exportar a Archivos.") }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, fileURL: file, options: nil)
        }
    }
}
#endif
