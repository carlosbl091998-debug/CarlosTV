package com.carlos.tv;

import android.content.Context;

import java.util.List;

/** Fuente local incluida con Carlos TV. */
public final class LocalCatalogBackend implements CatalogBackend {
    private final LocalCatalogRepository repository;

    public LocalCatalogBackend(Context context) {
        repository = new LocalCatalogRepository(context);
    }

    @Override
    public String getDisplayName() {
        return "biblioteca Carlos TV";
    }

    @Override
    public List<XuperProgram> load(Section section) throws Exception {
        switch (section) {
            case LIVE:
                return repository.getLive();
            case MOVIES:
                return repository.getMovies();
            case SERIES:
                return repository.getSeries();
            case HOME:
            default:
                return repository.getHome();
        }
    }

    @Override
    public XuperProgram resolveForPlayback(XuperProgram program) {
        return program;
    }
}
