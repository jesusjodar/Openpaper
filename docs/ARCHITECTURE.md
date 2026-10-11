# Decisiones técnicas

## Un paquete local y dos destinos

`App/OpenpaperApp.swift` compone las escenas nativas. `OpenpaperKit` contiene el dominio, Wallhaven, persistencia, servicios, vistas e Intents. Los dos destinos comparten código con compilación condicional exclusivamente en los límites de plataforma.

La navegación principal usa `TabView` superior nativa en Mac y adaptable en iPad; iPhone mantiene las pestañas inferiores. Cada destino tiene su `NavigationStack`. La ordenación actualiza el feed compartido: pestañas agrupadas en Mac, superiores en iPad amplio y selector segmentado o menú en compacto. Los filtros aplicados permanecen fuera del scroll del masonry; el formulario conserva borrador, Aplicar, Cancelar y Restablecer.

`MasonryColumns` distribuye por la columna más corta a partir de dimensiones originales y conserva el prefijo al paginar. Las columnas `LazyVStack` limitan vistas; la visibilidad de scroll controla cargas y materiales. El ancho se conoce antes de crear la cuadrícula, evitando materializar cientos de tarjetas durante la primera medición. La identidad visible se restaura al cambiar columnas.

## Estado y concurrencia

`AppSession` contiene los servicios y estado observable común. Dos `SearchFeed` conservan independientemente los resultados de Explorar y Buscar. No hay un modelo de vista por pantalla. UI, SwiftData y aplicación del escritorio viven en MainActor. El cliente y las colas son actores; red, descargas, reducción y recorte trabajan fuera del hilo principal.

La generación de consulta impide que resultados tardíos sustituyan a los actuales. La búsqueda espera 350 ms. Los archivos fuente comparten tareas por URL, independientemente del tamaño y de la descarga explícita. Cada consumidor registra su cancelación; el último cancela la transferencia. Las colas limitan a cuatro miniaturas y dos originales. La reducción tiene su propia cola de cuatro operaciones. El precargado conserva como máximo una página y se desactiva en ahorro de energía o redes caras/restringidas. Se vacía memoria al pasar a segundo plano o recibir presión de memoria en iOS.

La caché decodificada tiene límites de 64 MiB en móvil y 128 MiB en Mac; los archivos fuente de visualización en disco, 512 MiB y 1 GiB. Se fijan mientras se reducen o copian para que la poda no los retire en uso. La descarga explícita copia y valida el archivo en Originals sin recomprimir ni sustituir un original existente. Originals y Derived quedan fuera de la caché. Las miniaturas respetan tamaño real × escala y nunca amplían una fuente pequeña. El lienzo de detalle puede escalar para llenar la pantalla usando todos los píxeles disponibles del original.

## Materiales y detalle

SwiftUI `GlassEffectContainer(spacing: 0)` agrupa controles públicos. Un `NSGlassEffectContainerView` adicional es necesario para agrupar los `NSGlassEffectView` de las tarjetas de Mac: el contenedor SwiftUI no agrupa los representables de AppKit. Espaciado cero evita fusionar tarjetas vecinas. Hay una sola imagen bajo cada vidrio `.clear`, con interacción dirigida a la tarjeta y decoraciones separadas.

El puente Objective-C consulta `inputKeys`, protege excepciones KVC y modifica exclusivamente radio y opacidades de blur cuando existe el contrato completo. Conserva los valores anteriores, incluidas claves con valor nulo. El material agrupado solo se ajusta si todos sus efectos AppKit pertenecen a tarjetas propias, son `.clear` y permiten transparencia. La inspección excluye el contenido hospedado y sus controles. Observaciones acotadas de capas, layout, apariencia y activación de ventana agrupan ajustes; desmontar invalida observadores, cancela tareas y restaura valores. Debug y Release usan el mismo comportamiento. Sin contrato o con accesibilidad activa permanece el material nativo.

En móvil, el vidrio público se limita al perímetro y los indicadores. El detalle usa controles públicos circulares y una pill Aplicar/Guardar, con etiquetas y ayuda. La información conserva colecciones, etiquetas, autoría y enlaces identificados. Reutiliza la imagen cargada, reflejada verticalmente con capas de blur enmascaradas; reducción de transparencia o contraste aumentado sustituye esa zona por superficies semánticas.

## Proveedores y confianza

`WallpaperProvider` define búsqueda paginada y detalle. `ProviderCapabilities` declara operaciones opcionales; `WallhavenSearchOptions` aísla la sintaxis específica. Los endpoints adicionales de Wallhaven permanecen en su adaptador. No existe una interfaz de escritura remota porque la API no la documenta.

La API se espacía 1,5 segundos (hasta 40 peticiones/minuto) y aplica `Retry-After` ante 429. El 401 se muestra como error de autenticación. La clave se envía por cabecera. Las redirecciones autenticadas solo admiten hosts oficiales. Las respuestas/importaciones y URLs multimedia se validan antes de usarse. NSFW necesita activación y clave validada. `Hot` queda en un caso propio de la ordenación y una prueba separada de contrato.

## Persistencia, archivos y transferencia

SwiftData usa un esquema versionado local sin CloudKit. Los cambios se guardan expresamente y se revierten ante errores. Los originales descargados se validan como imágenes antes de moverse a su ubicación final. No se reemplaza un original existente. El recorte genera una copia JPEG independiente; el original mantiene sus bytes.

La transferencia versión 1 incluye identidades públicas y metadatos, favoritos, colecciones y búsquedas. No incluye originales, datos de reanudación ni rutas de almacenamiento. La importación valida todo antes de abrir una transacción, une pertenencias y favoritos, conserva nombres/opciones existentes y nunca elimina datos.

Keychain almacena la clave de forma local al dispositivo. Los permisos de Fotos se solicitan al guardar y solo para añadir.

## Límites de plataforma

`WallpaperApplicationService` permite sustituir el servicio del escritorio. `MacWallpaperService` usa NSWorkspace por monitor y ofrece restauración si el archivo sigue accesible. No promete control por Space. Photos utiliza la API pública en móvil. Los App Intents devuelven `IntentFile`; el horario móvil corresponde al usuario en Atajos.

La rotación funciona mientras el proceso está vivo. Su reloj comprueba una fecha límite; tras reposo no reproduce todos los intervalos perdidos. Cerrar la ventana no termina una app de Mac con `MenuBarExtra`, mientras que Salir sí lo hace. Sin originales aptos o monitores disponibles se conserva el fondo y se muestra un error recuperable.
