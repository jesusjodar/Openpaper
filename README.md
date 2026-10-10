# Openpaper

Fondos de pantalla para **macOS 27, iPadOS 27 e iOS 27**, con SwiftUI y componentes nativos de Liquid Glass. Descubre fondos en Wallhaven, guarda favoritos y colecciones locales, descarga originales y encuadra una copia para tu pantalla.

## Compilar y abrir

1. Abre `Openpaper.xcodeproj` en **Xcode 27**.
2. Selecciona `Openpaper-Mac` para Mac o `Openpaper-Mobile` para iPhone/iPad.
3. Pulsa Run. Para un dispositivo físico, elige tu equipo en Signing & Capabilities.

No hay dependencias externas. `OpenpaperKit` es el único paquete local compartido. Los dos esquemas están incluidos en el repositorio.

```sh
swift test --package-path OpenpaperKit --scratch-path /private/tmp/openpaper-tests
xcodebuild -project Openpaper.xcodeproj -scheme Openpaper-Mac -destination 'platform=macOS' -derivedDataPath /private/tmp/openpaper-mac CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Openpaper.xcodeproj -scheme Openpaper-Mobile -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/openpaper-mobile CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=OPENPAPER0 build
```

Las compilaciones en `/private/tmp` evitan metadatos de Finder/iCloud en los artefactos. `OPENPAPER0` es únicamente el espacio de nombres de firma ad hoc del simulador; un dispositivo físico necesita tu equipo real. El simulador necesita sus entitlements de firma para acceder al Llavero. Para ejecutar un artefacto de Mac construido sin firma, fírmalo localmente con `codesign --force --deep --sign - Openpaper.app`. Esto no lo notariza ni lo convierte en una distribución firmada.

## Usar Openpaper

1. **Explorar:** recientes, populares, tendencias y aleatorios. Abre un fondo para ver sus etiquetas, procedencia y acciones.
2. **Buscar:** escribe etiquetas o la sintaxis de Wallhaven; ajusta un borrador de filtros y pulsa Aplicar. Guarda búsquedas para volver a ellas.
3. **Biblioteca:** favoritos, descargas, colecciones locales y búsquedas. El menú permite crear colecciones y transferir la biblioteca mediante JSON.
4. **Ajustes:** valida tu clave API, activa contenido adicional si lo deseas y configura la rotación en Mac.

El inicio es SFW. Sketchy se habilita explícitamente. NSFW requiere clave validada y confirmación, además del filtro correspondiente. Los límites también se aplican a biblioteca, automatizaciones y Atajos. Las consultas incompatibles muestran un error sin reescribir tu texto.

Las colecciones remotas se presentan separadas de las locales: Biblioteca → Colecciones de Wallhaven. Introduce el usuario propietario; activa Mis colecciones para incluir tus colecciones privadas con la clave. Solo se envía el filtro admitido de contenido y la página. Para escribir favoritos o colecciones remotas, abre Wallhaven.

## Descargar y aplicar

Se conserva el original, sin recomprimir. El detalle muestra progreso, cancelación y reintento. Una cancelación conserva los datos de reanudación que proporcione URLSession; si el servidor no permite reanudar, el siguiente intento comienza desde cero. La identidad del proveedor evita originales duplicados.

**Mac:** selecciona un monitor o todos y elige Rellenar/Ajustar. Puedes restaurar el fondo anterior si sus archivos y monitores siguen disponibles. La API actúa por pantalla; macOS gestiona los Spaces. Encuadrar genera un archivo separado.

**iPhone/iPad:** guarda en Fotos (permiso de solo añadir), abre la imagen, pulsa Compartir → Usar como fondo de pantalla. Puedes exportar a Archivos o compartir la imagen con controles del sistema. [Procedimiento de Apple](https://developer.apple.com/wwdc26/wallpaper/).

**Atajos:** Obtener un fondo aleatorio, Obtener un fondo de una colección y Descargar un fondo entregan un archivo de imagen. Mac incorpora Aplicar un fondo en Mac. En móvil, conecta la imagen con la acción del sistema y configura el horario en Atajos.

## Datos y privacidad

- SwiftData local guarda metadatos, favoritos, colecciones y búsquedas.
- Application Support contiene originales, copias derivadas y datos de reanudación; las miniaturas viven en Caches.
- La clave API se guarda en Keychain y se envía por `X-API-Key`, nunca en la URL.
- La transferencia versionada excluye credenciales, rutas de archivos locales e imágenes. La importación valida primero y combina por identidad en una transacción sin reemplazar datos existentes.
- La limpieza de caché afecta exclusivamente a miniaturas. No se eliminan originales ni copias que puedan usarse en el escritorio.
- No hay analítica, servicios propios ni sincronización iCloud. Las peticiones van directamente a Wallhaven y su CDN.

## Automatización en Mac

Elige una colección local o una búsqueda guardada y un intervalo de 15 minutos, una hora, seis horas o un día. El menú de Mac ofrece Pausar, Reanudar y Cambiar ahora. La app sigue ejecutándose al cerrar su ventana; Salir detiene la rotación. Tras reposo se ejecuta como máximo un cambio pendiente.

## Estado de entrega

Esta entrega usa la versión **0.1.0** hasta completar todos los criterios de 1.0. El estado comprobado, las limitaciones y las pruebas pendientes están en [VERIFICATION.md](docs/VERIFICATION.md). Compilar no demuestra el funcionamiento de Fotos y Atajos en dispositivos físicos ni sustituye las mediciones con Instruments.

GitHub Actions compila los dos destinos con Xcode 27, ejecuta pruebas con datos controlados y conserva artefactos sin firma privada. La prueba de contrato real es manual: `python3 scripts/check-wallhaven.py`. El CI habitual no depende de Wallhaven.

## Licencia y fuentes

El código se publica bajo [MIT](LICENSE). **Las imágenes conservan los derechos de sus autores** y no se distribuyen con este repositorio. [Condiciones de Wallhaven](https://www.whvn.cc/terms), [API oficial](https://www.whvn.cc/help/api), [Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass).

Consulta [CONTRIBUTING.md](CONTRIBUTING.md), [decisiones técnicas](docs/ARCHITECTURE.md) y [especificación](docs/SPECIFICATION.md).
