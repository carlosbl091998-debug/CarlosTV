# Arquitectura observable de Xuper aplicada a Carlos TV

Este documento describe únicamente comportamiento y estructura visibles en la APK de referencia. No incluye credenciales, claves, endpoints privados ni mecanismos para evadir protecciones.

## Módulos observados

La APK está separada en módulos funcionales:

- `main`: inicio y navegación principal.
- `live`: televisión en vivo, búsqueda de canales, guía y programación.
- `vod`: películas, series, categorías, búsqueda, filtros y detalles.
- `mine`: perfil, cuenta, historial, ajustes y QR.
- `login`: autenticación y cambio de contraseña.
- `download`: descargas.

Carlos TV debe mantener la misma separación conceptual aunque la implementación sea propia.

## Flujo principal que sí podemos reproducir

1. Inicio / Home con contenido destacado.
2. Secciones independientes para Live, Movies y Series.
3. Búsqueda transversal por nombre y categoría.
4. Vista de detalle antes de reproducir cuando el backend lo permita.
5. Resolución de una serie a episodio reproducible.
6. Reproductor desacoplado del origen del catálogo.
7. Favoritos e historial almacenados por Carlos TV.
8. Perfil y configuración separados del catálogo.

## Reproducción

La APK de referencia incluye varios motores de reproducción y mensajes que permiten cambiar de reproductor si una fuente falla. Carlos TV ya usa Media3/ExoPlayer; la arquitectura debe permitir una estrategia de fallback en el futuro sin acoplarla al catálogo.

## Funciones observadas para fases posteriores

- Favoritos sincronizables.
- Lista / suscripciones.
- Bloqueo de canales.
- Control parental.
- EPG / guía de programación.
- Búsqueda por voz.
- QR de acceso entre dispositivos.
- Historial.
- Descargas.
- Notificaciones de programas/eventos.

Estas funciones requieren un backend autorizado si se desea sincronización entre dispositivos. Las funciones locales pueden implementarse directamente en Carlos TV.

## Backend

La APK no expone en texto plano un servidor utilizable dentro de su archivo de dominios de prueba. El binario contiene protección y la mayor parte de su lógica no aparece como código Java/Kotlin recompilable. Por ello Carlos TV no debe depender de copiar un endpoint oculto.

La solución correcta es usar `CatalogBackend` como contrato. Cada fuente autorizada implementará ese contrato y devolverá objetos `XuperProgram`/`XuperMedia` al resto de la app. La interfaz de usuario y el reproductor no necesitan conocer el protocolo concreto del servidor.

## Contrato mínimo

Un backend debe poder:

- devolver Home;
- devolver Live;
- devolver Movies;
- devolver Series;
- resolver un elemento antes de reproducirlo cuando sea necesario.

Con esta separación, si posteriormente se dispone de documentación o credenciales autorizadas de un proveedor, solo se agrega un adaptador nuevo; la aplicación móvil no se vuelve a diseñar.
