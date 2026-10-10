import SwiftUI

public struct SettingsView: View {
    @Bindable var session: AppSession
    @State private var apiKey = ""
    @State private var enablingNSFW = false
    @State private var disconnecting = false
    @State private var storage = "Calculando…"
    public init(session: AppSession) { self.session = session }
    public var body: some View {
        Form {
            if let message = session.message {
                Section("No se pudo completar la acción") { Text(message).foregroundStyle(.red); Button("Aceptar") { session.message = nil } }
            }
            if let notice = session.notice {
                Section("Resultado") { Text(notice); Button("Aceptar") { session.notice = nil } }
            }
            Section("Proveedor") {
                LabeledContent("Proveedor activo", value: "Wallhaven")
                Text("Openpaper usa la API pública. Las imágenes conservan los derechos de sus autores.").font(.caption).foregroundStyle(.secondary)
                Link("Cuenta y clave API en Wallhaven ↗", destination: URL(string: "https://wallhaven.cc/settings/account")!)
                SecureField("Clave API", text: $apiKey)
                    #if os(iOS)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    #endif
                HStack {
                    Button("Validar y guardar en Llavero") { Task { await session.connect(key: apiKey); if session.keyValidated { apiKey = "" } } }.disabled(apiKey.isEmpty || session.busy)
                    if session.busy { ProgressView() }
                }
                if session.hasKey {
                    Label(session.keyValidated ? "Clave validada" : "Clave guardada; validación pendiente", systemImage: session.keyValidated ? "checkmark.shield" : "key")
                    Button("Desconectar", role: .destructive) { disconnecting = true }
                    Button("Importar preferencias de la cuenta") { Task { await session.importAccountPreferences() } }.disabled(!session.keyValidated)
                }
            }
            Section {
                LabeledContent("Contenido inicial", value: "SFW")
                Toggle("Permitir Sketchy", isOn: Binding(get: { session.policy.sketchy }, set: { value in Task { await session.setPolicy(sketchy: value, nsfw: session.policy.nsfw) } }))
                Toggle("Permitir NSFW", isOn: Binding(get: { session.policy.nsfw }, set: { value in
                    if value { enablingNSFW = true }
                    else { Task { await session.setPolicy(sketchy: session.policy.sketchy, nsfw: false) } }
                })).disabled(!session.keyValidated)
            } header: { Text("Contenido permitido") } footer: { Text("Estos permisos también se aplican a biblioteca, descargas, rotación y Atajos. Las búsquedas guardadas conservan sus filtros; las combinaciones no permitidas mostrarán un error.") }
            Section("Almacenamiento y descargas") {
                LabeledContent("Originales locales", value: storage)
                Text("Los originales se conservan sin recomprimir. Hasta dos descargas y cuatro miniaturas simultáneas; las descargas canceladas se reanudan si el servidor lo permite.").font(.caption).foregroundStyle(.secondary)
                Button("Limpiar caché de miniaturas") {
                    Task { do { try await session.images?.clearDisk(); session.notice = "Caché de miniaturas eliminada. Los originales y copias del escritorio se conservan." } catch { session.message = error.localizedDescription } }
                }
                if !session.jobs.isEmpty {
                    ForEach(session.jobs.keys.sorted(), id: \.self) { key in
                        HStack { Text(key); ProgressView(value: session.jobs[key] ?? 0)
                            Button("Cancelar") { let parts = key.split(separator: ":"); if let id = parts.last { Task { await session.downloads?.cancel(.init(id: String(id))) } } }
                        }
                    }
                }
                Text("La transferencia de Biblioteca incluye favoritos, colecciones y búsquedas. Excluye claves, rutas locales e imágenes originales.").font(.caption).foregroundStyle(.secondary)
            }
            #if os(macOS)
            Section {
                Toggle("Rotación mientras Openpaper está ejecutándose", isOn: Binding(get: { session.rotationEnabled }, set: { session.configureRotation(enabled: $0) }))
                Picker("Fuente", selection: Binding(get: { session.rotationSource }, set: { session.configureRotation(source: $0) })) {
                    Text("Elige una fuente").tag("")
                    if let library = session.library {
                        ForEach(library.collections) { Text("Colección: \($0.name)").tag($0.id.uuidString) }
                        ForEach(library.searches) { Text("Búsqueda: \($0.name)").tag("search:\($0.id.uuidString)") }
                    }
                }
                Picker("Intervalo", selection: Binding(get: { session.rotationInterval }, set: { session.configureRotation(interval: $0) })) {
                    Text("15 minutos").tag(900); Text("Una hora").tag(3600); Text("6 horas").tag(21600); Text("Un día").tag(86400)
                }
                Picker("Orden", selection: Binding(get: { session.rotationRandom }, set: { session.configureRotation(random: $0) })) {
                    Text("Aleatorio sin repetir").tag(true); Text("Secuencial").tag(false)
                }
                Picker("Monitor", selection: Binding(get: { session.rotationTarget }, set: { session.configureRotation(target: $0) })) {
                    Text("Todos los conectados").tag("")
                    ForEach(session.application.screens) { Text($0.name).tag($0.id) }
                }
                HStack {
                    Button(session.rotationPaused ? "Reanudar" : "Pausar") { session.toggleRotation() }.disabled(!session.rotationEnabled)
                    Button("Cambiar ahora") { Task { await session.rotateNow() } }.disabled(session.rotationSource.isEmpty)
                }
                Text(session.rotationDescription).font(.caption)
            } header: { Text("Automatización en Mac") } footer: { Text("Cerrar la ventana permite continuar. Salir de Openpaper detiene la rotación. Tras reposo se hace como máximo un cambio pendiente. Sin red se usan los originales disponibles o se conserva el fondo actual. La API de macOS actúa por monitor y no controla individualmente todos los Spaces.") }
            #endif
            Section("Atajos") {
                Text("En Atajos, busca Openpaper y añade Obtener un fondo aleatorio, Obtener un fondo de una colección o Descargar un fondo. Conecta el archivo de imagen con la acción del sistema para establecer el fondo y configura allí el horario.")
                #if os(macOS)
                Text("También está disponible Aplicar un fondo en Mac.")
                #else
                Text("Para el flujo manual: guarda en Fotos, abre la imagen, pulsa Compartir y Usar como fondo de pantalla.")
                #endif
                Text("Las automatizaciones móviles necesitan configurarse y comprobarse en el dispositivo físico.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Acerca de Openpaper") {
                LabeledContent("Versión", value: "0.1.0 · Validación de 1.0 en curso")
                Link("Código y licencia MIT ↗", destination: URL(string: "https://github.com/jesusjodar/Openpaper")!)
                Link("API de Wallhaven ↗", destination: URL(string: "https://www.whvn.cc/help/api")!)
                Text("Datos locales. Sin analítica, iCloud ni servicios propios.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Ajustes")
        .confirmationDialog("¿Permitir contenido NSFW en Openpaper?", isPresented: $enablingNSFW, titleVisibility: .visible) {
            Button("Activar NSFW") { Task { await session.setPolicy(sketchy: session.policy.sketchy, nsfw: true) } }
            Button("Cancelar", role: .cancel) {}
        } message: { Text("Solo se mostrará si también está seleccionado en los filtros. Esta elección afecta a descargas, biblioteca, rotación y Atajos.") }
        .confirmationDialog("¿Eliminar la clave API del Llavero?", isPresented: $disconnecting, titleVisibility: .visible) {
            Button("Desconectar", role: .destructive) { Task { await session.disconnect() } }
        }
        .task {
            guard let root = session.library?.root else { return }
            let bytes = await Task.detached {
                let files = (try? FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Originals"), includingPropertiesForKeys: [.fileSizeKey])) ?? []
                return files.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
            }.value
            storage = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }
    }
}
