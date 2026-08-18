# Carlos TV v0.2

Aplicación Android tipo WebView que abre `https://rojadirectaa.net/` dentro de una interfaz propia.

## Mejoras de la versión 0.2

- Barra superior propia con nombre, icono y versión de Carlos TV.
- Navegación inferior nativa con Atrás, Inicio y Recargar.
- Pantalla de carga propia para evitar la apariencia de navegador.
- Bloqueo de ventanas emergentes, incluso las generadas al tocar la pantalla.
- Bloqueo local de dominios publicitarios comunes y limpieza de elementos invasivos.
- Reproducción de video HTML5 y modo de pantalla completa.
- Cookies, almacenamiento web y navegación interna.
- Compatibilidad desde Android 6.0 (API 23).

El filtrado publicitario es local y de mejor esfuerzo: el sitio puede cambiar sus dominios o scripts. La aplicación no descarga ni extrae transmisiones, no elimina protecciones y no controla el contenido del sitio externo. Úsala únicamente para contenido al que tengas acceso legítimo.

## Obtener el APK desde el celular

1. Abre la pestaña **Actions** del repositorio.
2. Entra al flujo **Compilar APK** más reciente.
3. En **Artifacts**, descarga `CarlosTV-v0.2-debug`.
4. Abre el ZIP descargado y toca `CarlosTV-v0.2-debug.apk`.
5. Si Android lo solicita, permite temporalmente **Instalar apps desconocidas** para tu navegador o gestor de archivos.

El APK de prueba queda disponible durante 30 días después de cada compilación. Cada cambio enviado a la rama `main` crea uno nuevo automáticamente.
