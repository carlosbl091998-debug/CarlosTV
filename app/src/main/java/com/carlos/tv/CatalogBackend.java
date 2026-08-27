package com.carlos.tv;

import java.util.List;

/**
 * Fuente de contenido intercambiable para Carlos TV.
 *
 * La interfaz representa únicamente comportamiento funcional observable:
 * inicio, TV en vivo, películas, series y resolución de un elemento antes de
 * reproducirlo. No contiene endpoints, claves ni detalles privados de ningún
 * proveedor concreto.
 */
public interface CatalogBackend {
    enum Section {
        HOME,
        LIVE,
        MOVIES,
        SERIES
    }

    /** Nombre corto mostrado en la interfaz. */
    String getDisplayName();

    /** Carga el contenido correspondiente a una sección. */
    List<XuperProgram> load(Section section) throws Exception;

    /**
     * Da oportunidad al backend de convertir un elemento de catálogo en un
     * elemento reproducible (por ejemplo, resolver el primer episodio de una
     * serie). Si no necesita resolución adicional, devuelve el mismo objeto.
     */
    XuperProgram resolveForPlayback(XuperProgram program) throws Exception;
}
