# Carlos TV v0.4

Aplicación Android nativa para organizar y reproducir señales abiertas en
español publicadas mediante listas M3U directas.

## Novedades de la versión 0.4

- Catálogo fijo en español; se eliminó la opción de importar listas.
- Fuente principal:
  https://www.m3u.cl/lista/MX.m3u
- Fuente secundaria tolerante a fallos:
  http://pl.pro/lista.m3u
- Si una fuente está caída, la otra continúa cargando normalmente.
- Normalización de nombres, país, idioma y categorías.
- Comprobación ligera en segundo plano para ocultar respuestas 400, 401, 403,
  404 y 410.
- Cuando el reproductor confirma que una señal falló, se oculta hasta la
  siguiente actualización manual.
- Caché independiente por fuente durante seis horas.
- Búsqueda, categorías, favoritos, pantalla completa y reproductor nativo
  Media3/ExoPlayer.
- Compatibilidad desde Android 6.0 (API 23).

## Filtrado de contenido

La lista de México se considera contenido en español porque está organizada
para México e incluye algunas señales abiertas latinoamericanas. En las demás
fuentes se conservan solamente canales cuyo idioma, país, nombre o categoría
indican contenido en español.

La comprobación de disponibilidad es deliberadamente conservadora: oculta
errores HTTP definitivos, pero conserva los tiempos de espera para evitar
eliminar canales que estén temporalmente saturados o restringidos por región.

## Fuentes y disponibilidad

Carlos TV no aloja ni retransmite video. Solamente consume URLs directas
publicadas por las fuentes configuradas. Cada señal puede cambiar, dejar de
funcionar o estar restringida por ubicación. La aplicación no evade DRM,
cuentas, tokens ni protecciones del proveedor.

## Obtener el APK

1. Abre la pestaña **Actions** del repositorio.
2. Entra al flujo **Compilar APK** más reciente.
3. Descarga el artefacto **CarlosTV-v0.4-debug**.
4. Abre el ZIP y toca **CarlosTV-v0.4-debug.apk**.

Cada cambio enviado a main inicia una compilación nueva.
