package com.carlos.tv;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

public final class XuperProgram {
    private final String id;
    private final String name;
    private final String category;
    private final String posterUrl;
    private final String country;
    private final List<XuperMedia> medias;

    public XuperProgram(String id, String name, String category, String posterUrl,
                        String country, List<XuperMedia> medias) {
        this.id = clean(id);
        this.name = clean(name).isEmpty() ? "Contenido sin nombre" : clean(name);
        this.category = clean(category).isEmpty() ? "Catálogo" : clean(category);
        this.posterUrl = clean(posterUrl);
        this.country = clean(country);
        this.medias = Collections.unmodifiableList(new ArrayList<>(medias));
    }

    private static String clean(String value) {
        return value == null ? "" : value.trim();
    }

    public String getId() { return id; }
    public String getName() { return name; }
    public String getCategory() { return category; }
    public String getPosterUrl() { return posterUrl; }
    public String getCountry() { return country; }
    public List<XuperMedia> getMedias() { return medias; }

    public XuperMedia chooseMedia() {
        XuperMedia fallback = null;
        for (XuperMedia media : medias) {
            if (!media.isPlayable()) continue;
            if (fallback == null) fallback = media;
            String q = media.getQuality().toLowerCase(java.util.Locale.US);
            if (q.contains("1080") || q.contains("720") || q.contains("hd")) {
                return media;
            }
        }
        return fallback;
    }
}
