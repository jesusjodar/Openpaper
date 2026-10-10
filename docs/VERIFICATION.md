# Verificación de 0.1.0

Fecha: 11 de octubre de 2026. Esta entrega es una **versión preliminar**, no la aceptación de 1.0.

## Comprobado

| Área | Evidencia |
|---|---|
| Compilación local | Xcode 27.0: Mac, iPhone/iPad Simulator y dispositivo iOS genérico compilan sin errores ni avisos. Los destinos de dispositivo y Mac se construyen sin firma privada. |
| Pruebas controladas | 14 pruebas Swift Testing pasan: filtros y sintaxis, contenido permitido, respuestas incompletas, autenticación y límites, consultas tardías, paginación, transferencia sin pérdidas, persistencia, duplicados, almacenamiento no utilizable, cancelación de cola, orden de rotación y recorte conservando bytes originales. |
| Contrato de Wallhaven | Prueba separada real: recientes, Hot, Toplist, aleatorios, resoluciones y proporciones múltiples, detalle y etiquetas. No descarga originales ni usa credenciales. |
| iPhone simulado | Arranque, cuadrícula, detalle, favorito persistido, descarga de PNG original, copia encuadrada y guardado en Fotos. El permiso solicitado es de solo añadir. La compilación final reconoce la resolución física simulada del destino y muestra controles de encuadre etiquetados. |
| iPad simulado | Barra lateral y cuadrícula adaptativa, navegación al detalle y cambio entre orientación vertical y horizontal. |
| Mac | Arranque con biblioteca local existente, cuadrícula y validación de filtros. La revisión de biblioteca y escritorio continúa antes de cerrar esta entrega. |

Las comprobaciones de simuladores se realizan **una a una**: se apaga iPhone antes de iniciar iPad. No se publican las imágenes descargadas, bibliotecas, capturas con datos personales ni claves.

## Particularidad del proveedor

La API real respondió con una semilla diferente en los metadatos de una página posterior, aunque recibió la semilla inicial. Openpaper conserva y envía la primera semilla y elimina IDs repetidos; no puede garantizar un orden que el servidor cambie. `Hot` está disponible en la prueba real, pero no figura en la enumeración de la documentación oficial. El contrato se comprueba manualmente con `python3 scripts/check-wallhaven.py`.

## Pendiente para aceptar 1.0

1. Ejecutar los cuatro flujos de Atajos y Fotos en iPhone/iPad físicos con firma del usuario; comprobar las acciones del sistema hasta aplicar el fondo.
2. Medir desplazamiento prolongado, memoria, red y energía con Instruments. Revisar VoiceOver completo, Dynamic Type extremo, teclado/trackpad, ventanas estrechas y preferencias de accesibilidad.
3. Comprobar interrupción real y reanudación de descargas, disco lleno, permiso de Fotos denegado y cambios de conectividad durante operaciones.
4. Comprobar rotación durante reposo real, cambios de monitores y fallos parciales de aplicación. La prueba controlada de orden no demuestra estos escenarios físicos.
5. Probar ajustes y colecciones privadas con una clave real y revisar activaciones explícitas de contenido adicional. No se ha usado una cuenta privada para verificar esta entrega.

## Límites y distribución

- Las descargas aceptan JPEG/PNG válidos hasta 300 MB; el recorte limita la imagen decodificada a 80 megapíxeles y siempre escribe una copia. Estos límites deben ajustarse a partir de mediciones.
- Los límites de caché y concurrencia están implementados; no se consideran todavía resultados de una medición de rendimiento.
- Atajos tiene metadatos extraídos durante la compilación; esto no demuestra su ejecución completa en dispositivos físicos.
- CI ejecuta pruebas controladas y las tres compilaciones. Sus ZIP de Mac y simulador son artefactos de desarrollo; Mac requiere firma ad hoc local para ejecutarlo. No hay distribución firmada, notarización ni paquete instalable para dispositivos iOS.
- No hay soporte individual por Space, ejecución de rotación con la app cerrada, sincronización iCloud ni escritura remota en Wallhaven.
