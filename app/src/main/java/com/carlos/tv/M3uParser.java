package com.carlos.tv;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class M3uParser {

    private static final int MAX_CHANNELS = 20_000;
    private static final Pattern ATTRIBUTE_PATTERN =
            Pattern.compile("([A-Za-z0-9_-]+)=\"([^\"]*)\"");

    public ParseResult parse(InputStream inputStream) throws IOException {
        List<Channel> channels = new ArrayList<>();
        BufferedReader reader = new BufferedReader(
                new InputStreamReader(inputStream, StandardCharsets.UTF_8));

        EntryInfo pending = null;
        int skipped = 0;
        String line;

        while ((line = reader.readLine()) != null && channels.size() < MAX_CHANNELS) {
            line = stripBom(line).trim();
            if (line.isEmpty()) {
                continue;
            }

            if (line.startsWith("#EXT-X-")) {
                throw new IOException(
                        "El archivo seleccionado es una sola señal HLS, no una lista de canales M3U.");
            }

            if (line.regionMatches(true, 0, "#EXTINF:", 0, 8)) {
                pending = parseInfo(line);
                continue;
            }

            if (line.startsWith("#")) {
                continue;
            }

            if (pending == null) {
                skipped++;
                continue;
            }

            String lower = line.toLowerCase(Locale.US);
            if (!lower.startsWith("https://") && !lower.startsWith("http://")) {
                skipped++;
                pending = null;
                continue;
            }

            channels.add(new Channel(
                    pending.name,
                    pending.category,
                    pending.country,
                    pending.language,
                    pending.logoUrl,
                    line));
            pending = null;
        }

        if (channels.isEmpty()) {
            throw new IOException("La lista no contiene canales HTTP o HTTPS compatibles.");
        }
        return new ParseResult(channels, skipped);
    }

    private EntryInfo parseInfo(String line) {
        Map<String, String> attributes = new HashMap<>();
        Matcher matcher = ATTRIBUTE_PATTERN.matcher(line);
        while (matcher.find()) {
            attributes.put(
                    matcher.group(1).toLowerCase(Locale.US),
                    matcher.group(2).trim());
        }

        int comma = line.lastIndexOf(',');
        String displayName = comma >= 0 ? line.substring(comma + 1).trim() : "";
        String tvgName = attributes.get("tvg-name");
        if (displayName.isEmpty() && tvgName != null) {
            displayName = tvgName;
        }

        String category = firstNonEmpty(
                attributes.get("group-title"),
                attributes.get("tvg-category"),
                attributes.get("tvg-country"),
                "Otros");

        return new EntryInfo(
                displayName,
                category,
                firstNonEmpty(attributes.get("tvg-country"), ""),
                firstNonEmpty(attributes.get("tvg-language"), ""),
                firstNonEmpty(attributes.get("tvg-logo"), ""));
    }

    private static String firstNonEmpty(String... values) {
        for (String value : values) {
            if (value != null && !value.trim().isEmpty()) {
                return value.trim();
            }
        }
        return "";
    }

    private static String stripBom(String value) {
        if (!value.isEmpty() && value.charAt(0) == '\uFEFF') {
            return value.substring(1);
        }
        return value;
    }

    public static final class ParseResult {
        private final List<Channel> channels;
        private final int skipped;

        private ParseResult(List<Channel> channels, int skipped) {
            this.channels = channels;
            this.skipped = skipped;
        }

        public List<Channel> getChannels() {
            return channels;
        }

        public int getSkipped() {
            return skipped;
        }
    }

    private static final class EntryInfo {
        private final String name;
        private final String category;
        private final String country;
        private final String language;
        private final String logoUrl;

        private EntryInfo(
                String name,
                String category,
                String country,
                String language,
                String logoUrl) {
            this.name = name;
            this.category = category;
            this.country = country;
            this.language = language;
            this.logoUrl = logoUrl;
        }
    }
}
