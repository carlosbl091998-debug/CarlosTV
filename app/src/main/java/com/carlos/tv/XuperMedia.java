package com.carlos.tv;

public final class XuperMedia {
    private final String url;
    private final String quality;
    private final String type;

    public XuperMedia(String url, String quality, String type) {
        this.url = clean(url);
        this.quality = clean(quality);
        this.type = clean(type);
    }

    private static String clean(String value) {
        return value == null ? "" : value.trim();
    }

    public String getUrl() { return url; }
    public String getQuality() { return quality; }
    public String getType() { return type; }
    public boolean isPlayable() {
        String lower = url.toLowerCase(java.util.Locale.US);
        return lower.startsWith("http://") || lower.startsWith("https://");
    }
}
