package com.carlos.tv;

import java.util.ArrayList;
import java.util.List;

public final class Channel {

    private final String name;
    private final String category;
    private final String country;
    private final String language;
    private final String logoUrl;
    private final String streamUrl;
    private boolean favorite;

    public Channel(
            String name,
            String category,
            String country,
            String language,
            String logoUrl,
            String streamUrl) {
        this.name = clean(name, "Canal sin nombre");
        this.category = clean(category, "Otros");
        this.country = clean(country, "");
        this.language = clean(language, "");
        this.logoUrl = clean(logoUrl, "");
        this.streamUrl = clean(streamUrl, "");
    }

    private static String clean(String value, String fallback) {
        if (value == null || value.trim().isEmpty()) {
            return fallback;
        }
        return value.trim();
    }

    public String getName() {
        return name;
    }

    public String getCategory() {
        return category;
    }

    public String getCountry() {
        return country;
    }

    public String getLanguage() {
        return language;
    }

    public String getLogoUrl() {
        return logoUrl;
    }

    public String getStreamUrl() {
        return streamUrl;
    }

    public boolean isFavorite() {
        return favorite;
    }

    public void setFavorite(boolean favorite) {
        this.favorite = favorite;
    }

    public String getMetadata() {
        List<String> parts = new ArrayList<>();
        if (!category.isEmpty() && !"Otros".equals(category)) {
            parts.add(category);
        }
        if (!country.isEmpty() && !parts.contains(country)) {
            parts.add(country);
        }
        if (!language.isEmpty() && !parts.contains(language)) {
            parts.add(language);
        }
        if (parts.isEmpty()) {
            return "Televisión en vivo";
        }
        StringBuilder metadata = new StringBuilder();
        for (String part : parts) {
            if (metadata.length() > 0) {
                metadata.append(" · ");
            }
            metadata.append(part);
        }
        return metadata.toString();
    }
}
