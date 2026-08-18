# Carlos TV v0.3

Aplicación Android nativa para organizar y reproducir listas de televisión en vivo que el usuario tenga autorización para utilizar.

## Novedades de la versión 0.3

- Nuevo logotipo original de Carlos TV.
- Interfaz nativa; ya no depende de una página WebView.
- Catálogo con búsqueda, categorías y favoritos.
- Reproductor Media3/ExoPlayer con HLS, DASH y video progresivo.
- Pantalla completa y controles de reproducción.
- Descarga inicial de la lista pública de IPTV-org:
  https://iptv-org.github.io/iptv/index.m3u
- Caché local de seis horas para abrir más rápido y funcionar si la actualización falla.
- Importación de archivos M3U propios desde el teléfono.
- Carga de logotipos de canales con respaldo visual cuando no están disponibles.
- Compatibilidad desde Android 6.0 (API 23).

## Formato recomendado

La app espera una lista M3U extendida. Cada canal debe tener una línea EXTINF
y, en la línea siguiente, un enlace directo HTTP o HTTPS. Los metadatos
recomendados son tvg-name, tvg-logo, tvg-country, tvg-language y group-title.

La lista general debe terminar normalmente en .m3u; cada señal HLS puede
terminar en .m3u8. Carlos TV no evade DRM, cuentas, tokens, restricciones del
proveedor ni protecciones contra uso externo.

## Fuente inicial y disponibilidad

IPTV-org describe su repositorio como una colección de enlaces a canales
públicamente disponibles y publica sus datos bajo CC0. Carlos TV no aloja ni
retransmite video. Cada señal pertenece a su proveedor y puede dejar de
funcionar, cambiar, estar restringida por región o requerir autorización.

## Obtener el APK

1. Abre la pestaña **Actions** del repositorio.
2. Entra al flujo **Compilar APK** más reciente.
3. Descarga el artefacto CarlosTV-v0.3-debug.
4. Abre el ZIP y toca CarlosTV-v0.3-debug.apk.

Cada cambio enviado a main inicia una compilación nueva.
