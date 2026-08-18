package com.carlos.tv;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class SpanishChannelFilter {

    private static final Pattern COUNTRY_SUFFIX =
            Pattern.compile("\\s*\\|\\s*([A-Za-z]{2})\\s*$");

    private static final Set<String> SPANISH_COUNTRY_CODES = new HashSet<>(Arrays.asList(
            "AR", "BO", "CL", "CO", "CR", "CU", "DO", "EC", "ES", "GQ",
            "GT", "HN", "MX", "NI", "PA", "PE", "PR", "PY", "SV", "UY", "VE"));

    private SpanishChannelFilter() {
    }

    public static List<Channel> filterAndNormalize(
            List<Channel> channels,
            boolean assumeSpanish) {
        List<Channel> filtered = new ArrayList<>();
        for (Channel channel : channels) {
            String countryCode = extractCountryCode(channel);
            if (!assumeSpanish && !looksSpanish(channel, countryCode)) {
                continue;
            }

            String cleanName = cleanName(channel.getName());
            String country = displayCountry(countryCode, channel.getCountry());
            String language = channel.getLanguage().trim().isEmpty()
                    ? "Español"
                    : normalizeLanguage(channel.getLanguage());
            String category = normalizeCategory(channel.getCategory(), cleanName, country);

            filtered.add(new Channel(
                    cleanName,
                    category,
                    country,
                    language,
                    channel.getLogoUrl(),
                    channel.getStreamUrl()));
        }
        return filtered;
    }

    private static String extractCountryCode(Channel channel) {
        Matcher suffix = COUNTRY_SUFFIX.matcher(channel.getName());
        if (suffix.find()) {
            return suffix.group(1).toUpperCase(Locale.ROOT);
        }

        String country = channel.getCountry().trim().toUpperCase(Locale.ROOT);
        return country.length() == 2 ? country : "";
    }

    private static boolean looksSpanish(Channel channel, String countryCode) {
        if (SPANISH_COUNTRY_CODES.contains(countryCode)) {
            return true;
        }

        String language = channel.getLanguage().toLowerCase(Locale.ROOT);
        if (language.equals("es")
                || language.equals("spa")
                || language.contains("español")
                || language.contains("spanish")
                || language.contains("castellano")) {
            return true;
        }

        String description = (channel.getName()
                + " "
                + channel.getCategory()
                + " "
                + channel.getCountry()).toLowerCase(Locale.ROOT);
        return containsAny(
                description,
                "latino", "latina", "español", "castellano", "mexic", "argentin",
                "bolivia", "chile", "colombia", "costa rica", "cuba", "dominican",
                "ecuador", "españa", "guatemala", "honduras", "nicaragua", "panama",
                "panamá", "paraguay", "peru", "perú", "puerto rico", "salvador",
                "uruguay", "venezuela");
    }

    private static String cleanName(String value) {
        String withoutCountry = COUNTRY_SUFFIX.matcher(value).replaceFirst("");
        return withoutCountry.replace("✪", "").replaceAll("\\s{2,}", " ").trim();
    }

    private static String normalizeLanguage(String value) {
        String lower = value.toLowerCase(Locale.ROOT);
        if (lower.equals("es")
                || lower.equals("spa")
                || lower.contains("spanish")
                || lower.contains("español")
                || lower.contains("castellano")) {
            return "Español";
        }
        return value.trim();
    }

    private static String normalizeCategory(String original, String name, String country) {
        String lowerName = name.toLowerCase(Locale.ROOT);
        if (containsAny(lowerName, "deporte", "sport", "fútbol", "futbol", "lucha")) {
            return "Deportes";
        }
        if (containsAny(
                lowerName,
                "noticia", "news", "informativo", "adn 40", "milenio", "canal 66")) {
            return "Noticias";
        }
        if (containsAny(
                lowerName,
                "música", "musica", "radio", "retro", "rewind", " fm", "teleritmo")) {
            return "Música";
        }
        if (containsAny(
                lowerName,
                "cultura", "cultural", "educa", "universidad", "canal once", "suyai")) {
            return "Cultura";
        }
        if (containsAny(lowerName, "infantil", "kids", "niños", "ninos")) {
            return "Infantil";
        }
        if (containsAny(lowerName, "relig", "crist", "alcance tv")) {
            return "Religiosos";
        }

        String cleanOriginal = original == null ? "" : original.trim();
        if (!cleanOriginal.isEmpty()
                && !"Otros".equalsIgnoreCase(cleanOriginal)
                && !cleanOriginal.equalsIgnoreCase(country)
                && !SPANISH_COUNTRY_CODES.contains(cleanOriginal.toUpperCase(Locale.ROOT))) {
            return cleanOriginal;
        }
        return "Regionales";
    }

    private static String displayCountry(String code, String fallback) {
        switch (code) {
            case "AR":
                return "Argentina";
            case "BO":
                return "Bolivia";
            case "CL":
                return "Chile";
            case "CO":
                return "Colombia";
            case "CR":
                return "Costa Rica";
            case "CU":
                return "Cuba";
            case "DO":
                return "República Dominicana";
            case "EC":
                return "Ecuador";
            case "ES":
                return "España";
            case "GT":
                return "Guatemala";
            case "HN":
                return "Honduras";
            case "MX":
                return "México";
            case "NI":
                return "Nicaragua";
            case "PA":
                return "Panamá";
            case "PE":
                return "Perú";
            case "PR":
                return "Puerto Rico";
            case "PY":
                return "Paraguay";
            case "SV":
                return "El Salvador";
            case "UY":
                return "Uruguay";
            case "VE":
                return "Venezuela";
            default:
                return fallback == null ? "" : fallback.trim();
        }
    }

    private static boolean containsAny(String value, String... candidates) {
        for (String candidate : candidates) {
            if (value.contains(candidate)) {
                return true;
            }
        }
        return false;
    }
}
