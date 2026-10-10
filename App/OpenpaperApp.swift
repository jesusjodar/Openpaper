import SwiftUI
import OpenpaperKit
import AppIntents

@main
struct OpenpaperApp: App {
    @State private var session: AppSession

    init() {
        let session = AppSession()
        _session = State(initialValue: session)
        AppDependencyManager.shared.add(dependency: session)
        OpenpaperShortcuts.updateAppShortcutParameters()
    }

    private var window: some Scene {
        #if os(macOS)
        WindowGroup {
            OpenpaperRoot(session: session)
                .frame(minWidth: 320, minHeight: 420)
        }
        .defaultSize(width: 1120, height: 780)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Buscar fondos") { session.destination = .search }
                    .keyboardShortcut("f", modifiers: .command)
                Button("Cambiar fondo ahora") { Task { await session.rotateNow() } }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
        #else
        WindowGroup { OpenpaperRoot(session: session) }
        #endif
    }

    var body: some Scene {
        window
        #if os(macOS)
        Settings { SettingsView(session: session).frame(width: 580, height: 640) }
        MenuBarExtra("Openpaper", systemImage: "photo.on.rectangle") {
            Text(session.rotationDescription)
            Button(session.rotationPaused ? "Reanudar" : "Pausar") { session.toggleRotation() }
                .disabled(!session.rotationEnabled)
            Button("Cambiar ahora") { Task { await session.rotateNow() } }
            Divider()
            Button("Salir de Openpaper") { NSApplication.shared.terminate(nil) }
        }
        #endif
    }
}
