# Openpaper: app nativa de fondos para Mac, iPad y iPhone

## 1. Objetivo y decisiones cerradas

Crear **Openpaper** para descubrir, organizar, descargar y usar fondos de pantalla, con integración inicial con Wallhaven y una arquitectura preparada para añadir proveedores.

- **Plataformas mínimas:** macOS 27, iPadOS 27 e iOS 27.
- **Interfaz:** exclusivamente SwiftUI, componentes nativos y Liquid Glass.
- **Publicación:** repositorio público `jesusjodar/Openpaper`, licencia MIT.
- **Datos:** locales; transferencia manual mediante exportación e importación.
- **Contenido:** todos los filtros, comenzando en SFW; contenido adicional mediante activación explícita.
- **Automatización:** rotación en Mac mientras la app siga ejecutándose y acciones de Atajos.
- **Encuadre:** vista previa y recorte de una copia, conservando el original.

**Estado comprobado:** la carpeta está vacía, aún no tiene Git y tienes Xcode 27 con los SDK necesarios. No se ha encontrado un repositorio `jesusjodar/Openpaper` en tu cuenta.

La integración cubrirá las funciones disponibles en la API de Wallhaven. Las operaciones exclusivas de su web tendrán enlaces externos claramente identificados.

## 2. Diseño y experiencia de uso

### Estructura principal

Tres destinos principales: **Explorar**, **Buscar** y **Biblioteca**. Los ajustes tendrán su ubicación habitual en cada plataforma.

| Plataforma | Navegación y presentación |
|---|---|
| **Mac** | `NavigationSplitView`, barra lateral, cuadrícula y detalle. Barra de herramientas, menús, atajos, ventanas redimensionables y ajustes mediante `Settings`. |
| **iPad** | Navegación con barra lateral cuando haya espacio; adaptación a ventanas estrechas. Compatibilidad con orientación, teclado, trackpad y arrastre de archivos. |
| **iPhone** | `TabView` y `NavigationStack`. Detalle independiente y filtros en una hoja nativa. Acciones principales accesibles sin saturar la pantalla. |

Estas decisiones siguen las recomendaciones de Apple para [macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos), [iPadOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-ipados) e [iOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-ios).

### Reglas visuales

- Las imágenes serán el centro de la experiencia: cuadrícula adaptable, espaciado uniforme y metadatos secundarios.
- Tipografía, colores semánticos, SF Symbols y controles del sistema.
- Liquid Glass en navegación y controles; las miniaturas conservarán una presentación sencilla.
- Usar el material que proporcionan los componentes estándar; evitar superponer efectos o añadir fondos que interfieran con ellos.
- Respetar apariencia clara/oscura, preferencias de Liquid Glass, reducción de movimiento/transparencia y contraste aumentado.
- Incorporar accesibilidad desde el inicio: VoiceOver, Dynamic Type, navegación por teclado y etiquetas comprensibles.

Apple recomienda adoptar el diseño con componentes estándar y usar Liquid Glass con moderación. [Guía de adopción](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass).

### Pantallas y comportamiento

1. **Explorar:** recientes, populares, tendencias y aleatorios; acceso al detalle desde cualquier imagen.
2. **Buscar:** campo nativo, historial, búsquedas guardadas y resumen de filtros activos.
3. **Filtros:** formulario agrupado; editar un borrador y pulsar **Aplicar**, con opción **Restablecer**.
4. **Detalle:** imagen ampliable, resolución, formato, tamaño, etiquetas, colores, procedencia y usuario que la subió.
5. **Biblioteca:** favoritos, colecciones locales, descargas y búsquedas guardadas.
6. **Ajustes:** proveedor, clave API, contenido permitido, almacenamiento, descargas y automatización.

Cada pantalla distinguirá carga, ausencia de resultados, falta de conexión y errores recuperables. Al volver desde el detalle se conservarán filtros, resultados y posición de desplazamiento.

## 3. Funciones de la primera versión completa

### Wallhaven

Implementar la siguiente cobertura:

| Área | Funciones |
|---|---|
| Categorías | General, Anime y People, combinables. |
| Contenido | SFW, Sketchy y NSFW; este último requiere clave válida. |
| Ordenación | Fecha, relevancia, aleatorio, visitas, favoritos, Toplist y Hot. |
| Dirección | Ascendente y descendente. |
| Toplist | 1 día, 3 días, semana, mes, 3 meses, 6 meses y año. |
| Resolución | Mínima o resoluciones exactas, incluidas personalizadas. |
| Proporción | Relaciones de aspecto y selección múltiple cuando esté admitida. |
| Color | Paleta admitida por el proveedor. |
| Consulta | Inclusiones, exclusiones, usuario, etiqueta exacta, formato y fondos similares. |
| Paginación | Metadatos del servidor y conservación de la semilla aleatoria. |

La referencia será la [API oficial](https://www.whvn.cc/help/api). `Hot` respondió correctamente en la comprobación directa, aunque no aparece en su enumeración documentada; quedará aislado y cubierto por una prueba de contrato.

Además:

- Navegación por etiquetas, usuario y fondos similares.
- Lectura de ajustes y colecciones propias; acceso a colecciones públicas de otros usuarios.
- Conexión mediante clave guardada en Keychain y enviada por `X-API-Key`.
- Importación voluntaria de preferencias de la cuenta, manteniendo SFW como configuración inicial.
- API: búsqueda, detalle, etiquetas, ajustes y colecciones.
- Colecciones remotas: respetar sus filtros disponibles y presentarlas separadas de las locales.
- Sin escritura remota de favoritos, colecciones, ajustes o subidas: no está documentada. Abrir Wallhaven para esas operaciones.
- Limitar las peticiones por debajo de las **45/minuto** documentadas y gestionar respuestas `401` y `429`. [Documentación](https://www.whvn.cc/help/api).

La búsqueda avanzada conservará la sintaxis original y explicará las combinaciones inválidas, sin modificar silenciosamente la intención del usuario.

### Descargas y biblioteca

- Descargar el original sin recomprimirlo por defecto.
- Mostrar progreso, cancelar y reintentar; reanudar cuando el servidor lo permita.
- Guardar en la biblioteca interna y exportar a Finder, Archivos o Fotos.
- Compartir la imagen o su enlace mediante las funciones nativas.
- Evitar descargas duplicadas mediante la identidad `proveedor + ID`.
- Crear, renombrar y eliminar colecciones locales; selección múltiple para organizar y descargar.
- Mantener favoritos y metadatos disponibles sin conexión.
- Distinguir claramente entre **favorito**, **descargado** y **aplicado en Mac**.

El archivo de transferencia contendrá favoritos, colecciones y búsquedas guardadas, con versión de formato. Excluirá credenciales, rutas privadas e imágenes originales. La importación combinará por identidad y no sobrescribirá la biblioteca existente.

### Aplicación y encuadre

| Plataforma | Comportamiento |
|---|---|
| **Mac** | Aplicar al monitor elegido o a todos los conectados; elegir ajustar o rellenar y ofrecer volver al fondo anterior cuando siga disponible. |
| **iPhone/iPad** | Guardar en Fotos y mostrar el procedimiento para usarlo como fondo. |
| **Atajos** | Entregar una imagen a las acciones del sistema para que el usuario configure su aplicación o automatización. |

En Mac se utilizará `NSWorkspace.setDesktopImageURL`, aislado como servicio de plataforma. Esto requiere AppKit para la operación del sistema, manteniendo toda la interfaz en SwiftUI. La API actúa por pantalla; no se prometerá control individual de todos los Spaces. [API de Apple](https://developer.apple.com/documentation/appkit/nsworkspace/setdesktopimageurl(_:for:options:)).

Para iPhone/iPad, el flujo base seguirá el procedimiento documentado por Apple desde Fotos; no dependerá de APIs privadas. [Procedimiento oficial](https://developer.apple.com/wwdc26/wallpaper/).

El encuadre permitirá zoom y desplazamiento con gestos SwiftUI, según la pantalla de destino. Generará una copia derivada y advertirá cuando la resolución sea insuficiente. La previsualización será orientativa: el sistema puede ajustar después el resultado.

### Automatización

**Mac**

- Fuente: colección local o búsqueda guardada.
- Intervalos: 15 minutos, una hora, seis horas o un día.
- Orden secuencial o aleatorio sin repetir hasta agotar el conjunto.
- Controles **Pausar**, **Reanudar** y **Cambiar ahora**.
- `MenuBarExtra` para acceder a estas acciones.
- Cerrar la ventana permitirá seguir rotando si la función está activa; **Salir** detendrá la app.
- Tras reposo, realizar como máximo un cambio pendiente.
- Sin conexión, usar originales locales disponibles o conservar el fondo actual.

**Atajos**

Publicar App Intents para **Obtener un fondo aleatorio**, **Obtener un fondo de una colección**, **Descargar un fondo** y **Aplicar un fondo en Mac**. Las acciones devolverán un archivo de imagen y respetarán los filtros de contenido.

La configuración del fondo y de los horarios en iPhone/iPad permanecerá en Atajos, con instrucciones dentro de Openpaper. Se verificará el flujo real en dispositivos. [Automatización con Atajos](https://support.apple.com/en-euro/guide/iphone/iph47e1c9d7d/27/ios/27).

## 4. Arquitectura, rendimiento y repositorio

### Organización del código

Un proyecto **`Openpaper.xcodeproj`**, con destinos nativos para Mac y para iPhone/iPad, y un único paquete local compartido.

Separación por responsabilidad:

- **Dominio:** fondos, identidad del proveedor, búsquedas, colecciones y capacidades.
- **Proveedores:** cliente Wallhaven, traducción de consultas y decodificación.
- **Servicios:** imágenes, descargas, persistencia, exportación y automatización.
- **Funciones SwiftUI:** explorar, buscar, detalle, biblioteca y ajustes.

Usar Swift, concurrencia estructurada y Observation. Los estados de interfaz vivirán en `MainActor`; red, decodificación y procesamiento de imágenes se ejecutarán fuera del hilo principal.

Evitar capas redundantes, clases base, singletons globales y un ViewModel por cada vista. Crear protocolos únicamente en límites que permitan sustituir un proveedor, un servicio de plataforma o una dependencia de pruebas.

### Interfaces necesarias

- `WallpaperProvider`: búsqueda paginada y detalle.
- Capacidades declaradas por proveedor para filtros y operaciones opcionales.
- `WallhavenSearchOptions`: opciones específicas sin contaminar el modelo común.
- `ImagePipeline`: carga, cancelación, reducción de tamaño y caché.
- `DownloadService`: descarga persistente y exportación.
- `WallpaperApplicationService`: aplicación disponible según plataforma.

Los proveedores futuros se añadirán como adaptadores compilados. La primera versión no incluirá un sistema de plugins descargables ni otros proveedores.

### Persistencia y privacidad

SwiftData local para biblioteca y metadatos; originales en Application Support, miniaturas en caché y credenciales en Keychain.

Solicitar permiso de Fotos únicamente al guardar, con acceso de **solo añadir**. Usar selectores nativos para exportaciones. No incluir analítica ni servicios propios.

La limpieza de caché no eliminará originales descargados ni fondos necesarios para mantener el escritorio. Las acciones destructivas de biblioteca pedirán confirmación.

### Rendimiento

- Cuadrícula con `LazyVGrid`; cargar miniaturas, no originales.
- Reducir imágenes al tamaño necesario antes de decodificarlas para pantalla.
- Compartir peticiones idénticas y cancelar trabajo que ya no sea necesario.
- Precargar como máximo la siguiente página.
- Búsqueda textual con debounce de 350 ms y cancelación de consultas anteriores.
- Máximo inicial: cuatro cargas de miniaturas y dos descargas originales simultáneas.
- Caché de imágenes decodificadas: 64 MB en iPhone/iPad y 128 MB en Mac; disco: 512 MB y 1 GB respectivamente.
- Reducir trabajo anticipado con poca memoria, ahorro de energía o red restringida.
- Proteger los resultados frente a respuestas tardías de búsquedas anteriores.

Estos límites serán valores iniciales ajustables tras medir con Instruments. La eficiencia se evaluará por fluidez, memoria, energía y red.

### GitHub

1. Inicializar Git con rama `main` y exclusiones para datos personales, credenciales y artefactos.
2. Crear y conectar el repositorio público `jesusjodar/Openpaper`.
3. Publicar licencia MIT, README, guía de compilación, contribución y decisiones técnicas.
4. Configurar CI para compilar y probar los destinos con Xcode 27, sin firma privada.
5. Publicar hitos, etiquetas y notas de versión.

El código tendrá licencia MIT; las imágenes conservarán sus derechos originales. [Condiciones de Wallhaven](https://www.whvn.cc/terms).

La entrega inicial será el código compilable y los artefactos de CI claramente identificados. La instalación en iPhone/iPad requerirá firma del usuario desde Xcode. La distribución firmada y notarizada para Mac queda fuera de esta primera entrega.

## 5. Fases y criterios de aceptación

| Fase | Entrega verificable |
|---|---|
| **1. Base** | Repositorio sincronizado, proyecto, arquitectura mínima, navegación y CI. |
| **2. Descubrimiento** | Wallhaven, búsquedas, filtros, paginación y detalle en las tres plataformas. |
| **3. Biblioteca** | Favoritos, colecciones, descargas, uso sin conexión y transferencia manual. |
| **4. Fondos** | Encuadre, aplicación multimonitor en Mac y guardado en Fotos/Archivos. |
| **5. Automatización** | Rotación, menú de Mac y App Intents. |
| **6. Versión 1.0** | Accesibilidad, mediciones, correcciones y documentación de uso. |

**Pruebas necesarias**

- Traducción de todos los filtros, consultas especiales y combinaciones incompatibles.
- Decodificación de respuestas incompletas, paginación, semillas y cambios de consulta.
- Fallos de autenticación, límites de peticiones, desconexiones y respuestas tardías.
- Descargas interrumpidas, duplicados, falta de espacio y permisos denegados.
- Persistencia, migraciones e importación sin pérdida de datos.
- Encuadre y exportación conservando el original.
- Rotación tras reposo, monitores desconectados y fuentes vacías.
- Flujo completo de Atajos en iPhone/iPad físicos.

Las pruebas automatizadas usarán datos controlados; las comprobaciones contra Wallhaven serán separadas para evitar depender del servicio en CI.

**La versión 1.0 estará terminada cuando:**

- Compile y funcione en las tres plataformas.
- Permita completar los flujos de descubrimiento, organización y descarga.
- Aplique correctamente el fondo en Mac y permita completar el flujo móvil documentado.
- Mantenga una biblioteca utilizable sin conexión y transferible manualmente.
- Supere la revisión visual y de accesibilidad en tamaños de ventana y ajustes del sistema distintos.
- Mantenga desplazamiento fluido, sin bloqueos de procesamiento de imágenes ni crecimiento sostenido de memoria.
- Tenga código, documentación y verificaciones sincronizados en GitHub.

**Fuera de esta versión:** iCloud, publicación en App Store, agente persistente, edición avanzada de imágenes y proveedores adicionales.
