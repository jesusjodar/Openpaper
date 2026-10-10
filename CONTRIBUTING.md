# Contribuir

Abre un issue con el problema observable, la plataforma y los pasos para reproducirlo. No adjuntes claves API, exportaciones personales, bases de datos ni imágenes cuyos derechos no tengas.

Antes de enviar un cambio, ejecuta las pruebas del paquete y compila ambos esquemas como se indica en el README. Añade pruebas con datos controlados para lógica nueva o correcciones. Mantén toda la interfaz en SwiftUI; AppKit y Photos se usan solo en los servicios de plataforma.

Los cambios en la persistencia necesitan una versión de esquema y una migración que conserve los datos. La transferencia de biblioteca tiene una versión independiente. Los nuevos proveedores serán adaptadores compilados con capacidades declaradas; no plugins descargables.

Describe las comprobaciones reales y lo que siga pendiente. Las pruebas contra Wallhaven son independientes del CI habitual. El proyecto no acepta credenciales de firma privada ni dependencias innecesarias.
