# Verificación de 0.1.0

Fecha: 11 de octubre de 2026. Esta entrega es una **versión preliminar**, no la aceptación de 1.0.

## Comprobado

| Área | Evidencia |
|---|---|
| Compilación local | Xcode 27.0: Mac Debug/Release, iPhone/iPad Simulator y dispositivo iOS genérico compilan sin errores ni avisos. Los destinos de dispositivo y Mac se construyen sin firma privada. |
| Pruebas controladas | 24 pruebas Swift Testing pasan: las 14 anteriores y 10 de masonry/paginación estable, tamaño Retina y fuentes pequeñas, fuente compartida entre tamaños y descarga, conservación de originales, límite de dos originales, reanudación anterior, cancelación por consumidores, contrato KVC protegido, reconstrucción de material, agrupación nativa y virtualización de 2.000 fondos. Tres comprobaciones con material real requieren una sesión gráfica de Mac. |
| Contrato de Wallhaven | Prueba separada real: recientes, Hot, Toplist, aleatorios, resoluciones y proporciones múltiples, detalle y etiquetas. No descarga originales ni usa credenciales. |
| iPhone simulado | Masonry, detalle a pantalla completa con título blanco y controles centrados, favorito persistido, descarga de PNG original, copia encuadrada y guardado en Fotos con instrucciones. Permiso de solo añadir. Revisado texto máximo de accesibilidad, contraste aumentado, ambas apariencias y orientación horizontal. |
| iPad simulado | Pestañas principales y de ordenación superiores nativas en vertical y horizontal; masonry, cabecera de filtros fija, detalle centrado y zona informativa reflejada/desenfocada. |
| Mac | Arranque con biblioteca existente, pestañas superiores integradas, masonry, imágenes nítidas con refracción en ventana activa, filtro de color y Cancelar, desplazamiento y paginación. La herramienta de inspección visual falla al recorrer el árbol de accesibilidad del detalle; la app permanece viva. El detalle Mac compila, pero su composición visual y sus acciones requieren revisión manual. |

Las comprobaciones de simuladores se realizan **una a una**: se apaga iPhone antes de iniciar iPad. No se publican las imágenes descargadas, bibliotecas, capturas con datos personales ni claves.

## Repetir las pruebas del material

```sh
OPENPAPER_GLASS_SYSTEM_TEST=1 swift test --package-path OpenpaperKit --scratch-path /private/tmp/openpaper-glass-tests
```

Requiere el Mac desbloqueado y WindowServer. El CI habitual ejecuta 21 pruebas controladas y omite esas tres pruebas gráficas. Los tests del puente incluyen claves ausentes y excepciones de lectura/escritura, valores nulos y parámetros no autorizados intactos. El test nativo usa material AppKit real y comprueba observadores liberados. La cuadrícula de 2.000 elementos mantiene entre 1 y 19 vidrios nativos activos en una ventana de 600 × 400 puntos; esto comprueba virtualización, no una reducción porcentual de GPU.

## Perfilado inicial

Time Profiler, Release en Mac, sesión de 40 segundos con desplazamiento y segunda página: 1.238 muestras de CPU y ningún registro de bloqueo superior a 250 ms. Activity Monitor registró 30 segundos de cuadrícula en reposo: huella física entre 112,30 y 112,35 MiB. Una segunda captura de Activity Monitor de 20 segundos, con desplazamiento y ampliación de 24 a 48 resultados, registró entre 140,36 y 234,74 MiB y 1,27 segundos de CPU acumulada. Estas sesiones cortas no sustituyen un ensayo prolongado ni comparan GPU con la versión anterior.

Allocations no llegó a completar la conexión y se detuvo. La plantilla Network solicita capturar tráfico HTTP de todo el Mac; se canceló sin aceptar esa captura. La reutilización y el límite de transferencias quedan verificados mediante contadores en pruebas controladas. No se publica ningún trace: puede incluir entorno, rutas y datos privados.

## Particularidad del proveedor

La API real respondió con una semilla diferente en los metadatos de una página posterior, aunque recibió la semilla inicial. Openpaper conserva y envía la primera semilla y elimina IDs repetidos; no puede garantizar un orden que el servidor cambie. `Hot` está disponible en la prueba real, pero no figura en la enumeración de la documentación oficial. El contrato se comprueba manualmente con `python3 scripts/check-wallhaven.py`.

## Pendiente para aceptar 1.0

1. Ejecutar los cuatro flujos de Atajos y Fotos en iPhone/iPad físicos con firma del usuario; comprobar las acciones del sistema hasta aplicar el fondo.
2. Completar mediciones prolongadas de memoria, red, GPU y energía. Revisar VoiceOver completo, teclado/trackpad y ventanas estrechas de Mac; sus dos apariencias y preferencias reales de accesibilidad siguen pendientes.
3. Comprobar interrupción real y reanudación de descargas, disco lleno, permiso de Fotos denegado y cambios de conectividad durante operaciones.
4. Comprobar rotación durante reposo real, cambios de monitores y fallos parciales de aplicación. La prueba controlada de orden no demuestra estos escenarios físicos.
5. Probar ajustes y colecciones privadas con una clave real y revisar activaciones explícitas de contenido adicional. No se ha usado una cuenta privada para verificar esta entrega.

## Límites y distribución

- Las descargas aceptan JPEG/PNG válidos hasta 300 MB; el recorte limita la imagen decodificada a 80 megapíxeles y siempre escribe una copia. Estos límites deben ajustarse a partir de mediciones.
- Los límites de caché y concurrencia están implementados y probados. Las mediciones iniciales son cortas y no demuestran estabilidad durante horas.
- El ajuste de blur usa API privada de Mac en Debug y Release. Si cambia el contrato, vuelve al material nativo, incluido su desenfoque. En una ventana inactiva, AppKit puede usar otro material y conservarlo sin ajuste. La refracción del perímetro y sus reflejos siguen siendo del sistema.
- Atajos tiene metadatos extraídos durante la compilación; esto no demuestra su ejecución completa en dispositivos físicos.
- CI ejecuta pruebas controladas y cuatro compilaciones (Mac Debug/Release, simulador y dispositivo). Sus ZIP de Mac y simulador son artefactos de desarrollo; Mac requiere firma ad hoc local para ejecutarlo. No hay distribución firmada, notarización ni paquete instalable para dispositivos iOS.
- No hay soporte individual por Space, ejecución de rotación con la app cerrada, sincronización iCloud ni escritura remota en Wallhaven.
