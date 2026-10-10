# Decisiones técnicas

## Un paquete local y dos destinos

`App/OpenpaperApp.swift` compone las escenas nativas. `OpenpaperKit` contiene el dominio, Wallhaven, persistencia, servicios, vistas e Intents. Los dos destinos comparten código con compilación condicional exclusivamente en los límites de plataforma.

La interfaz usa `NavigationSplitView` en Mac/iPad amplio y `TabView`/`NavigationStack` en iPhone y ventanas compactas. Las barras, menús, formularios, alertas y exportaciones usan componentes SwiftUI del sistema para adoptar Liquid Glass y las preferencias de accesibilidad sin materiales superpuestos.

## Estado y concurrencia

`AppSession` contiene los servicios y estado observable común. Dos `SearchFeed` conservan independientemente los resultados de Explorar y Buscar. No hay un modelo de vista por pantalla. UI, SwiftData y aplicación del escritorio viven en MainActor. El cliente y las colas son actores; red, descargas, reducción y recorte trabajan fuera del hilo principal.

La generación de consulta impide que resultados tardíos sustituyan a los actuales. La búsqueda espera 350 ms. Las miniaturas comparten tareas por URL/tamaño; se cancela una petición cuando ya no tiene consumidores. Las colas limitan a cuatro miniaturas y dos originales. El precargado conserva como máximo una página y se desactiva en ahorro de energía o redes caras/restringidas. Se vacía memoria al pasar a segundo plano o recibir presión de memoria en iOS.

La caché decodificada tiene límites de 64 MiB en móvil y 128 MiB en Mac; la caché en disco, de 512 MiB y 1 GiB. Los originales están fuera de ella. Estos límites necesitan mediciones con Instruments antes de 1.0.

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
