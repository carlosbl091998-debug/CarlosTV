package com.carlos.tv;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Set;

/** Parser tolerante para las distintas respuestas de catálogo observadas en Xuper. */
public final class XuperCatalogParser {

    public List<XuperProgram> parse(String json) throws JSONException {
        Object root = json.trim().startsWith("[") ? new JSONArray(json) : new JSONObject(json);
        List<XuperProgram> programs = new ArrayList<>();
        Set<String> seen = new HashSet<>();
        walk(root, "Catálogo", programs, seen, 0);
        return programs;
    }

    private void walk(Object node, String inheritedCategory, List<XuperProgram> out,
                      Set<String> seen, int depth) throws JSONException {
        if (node == null || depth > 14) return;

        if (node instanceof JSONArray) {
            JSONArray array = (JSONArray) node;
            for (int i = 0; i < array.length(); i++) {
                walk(array.opt(i), inheritedCategory, out, seen, depth + 1);
            }
            return;
        }

        if (!(node instanceof JSONObject)) return;
        JSONObject object = (JSONObject) node;

        String category = firstString(object,
                "columnName", "categoryName", "category", "groupName", "shelveName", "title");
        if (category.isEmpty()) category = inheritedCategory;

        XuperProgram program = toProgram(object, category);
        if (program != null) {
            String key = !program.getId().isEmpty()
                    ? program.getId()
                    : program.getName() + "|" + program.getCategory();
            if (seen.add(key)) out.add(program);
        }

        Iterator<String> keys = object.keys();
        while (keys.hasNext()) {
            String key = keys.next();
            Object child = object.opt(key);
            if (child instanceof JSONObject || child instanceof JSONArray) {
                walk(child, category, out, seen, depth + 1);
            }
        }
    }

    private XuperProgram toProgram(JSONObject o, String inheritedCategory) {
        String name = firstString(o, "programName", "name", "title", "contentName", "channelName");
        String id = firstString(o, "programId", "contentId", "id", "programCode", "program_code");
        String poster = firstString(o, "image", "poster", "posterUrl", "cover", "coverUrl", "logo", "icon");
        String country = firstString(o, "country", "nation", "area");
        String type = firstString(o, "programType", "type", "contentType");
        String category = firstString(o, "columnName", "categoryName", "category", "groupName");
        if (category.isEmpty()) category = inheritedCategory;
        if (!type.isEmpty() && (category.isEmpty() || "Catálogo".equals(category))) category = normalizeType(type);

        List<XuperMedia> medias = extractMedias(o);
        String direct = firstString(o, "media", "playUrl", "streamUrl", "url");
        if (looksUrl(direct) && medias.isEmpty()) medias.add(new XuperMedia(direct, "", type));

        boolean programLike = !name.isEmpty() && (!id.isEmpty() || !medias.isEmpty()
                || hasAny(o, "programType", "contentId", "programId", "programCode", "medias"));
        if (!programLike) return null;
        return new XuperProgram(id, name, category, poster, country, medias);
    }

    private List<XuperMedia> extractMedias(JSONObject o) {
        List<XuperMedia> result = new ArrayList<>();
        Object mediaNode = firstValue(o, "medias", "mediaList", "playList", "streams", "sources");
        if (mediaNode instanceof JSONArray) {
            JSONArray a = (JSONArray) mediaNode;
            for (int i = 0; i < a.length(); i++) {
                Object value = a.opt(i);
                if (value instanceof JSONObject) {
                    JSONObject m = (JSONObject) value;
                    String url = firstString(m, "name", "url", "media", "playUrl", "streamUrl");
                    if (looksUrl(url)) {
                        result.add(new XuperMedia(url,
                                firstString(m, "quality", "definition", "resolution"),
                                firstString(m, "type", "format", "mediaType")));
                    }
                } else if (value instanceof String && looksUrl((String) value)) {
                    result.add(new XuperMedia((String) value, "", ""));
                }
            }
        }
        return result;
    }

    private static boolean hasAny(JSONObject o, String... keys) {
        for (String key : keys) if (o.has(key) && !o.isNull(key)) return true;
        return false;
    }

    private static Object firstValue(JSONObject o, String... keys) {
        for (String key : keys) {
            if (o.has(key) && !o.isNull(key)) return o.opt(key);
        }
        return null;
    }

    private static String firstString(JSONObject o, String... keys) {
        for (String key : keys) {
            Object value = o.opt(key);
            if (value != null && value != JSONObject.NULL) {
                String text = String.valueOf(value).trim();
                if (!text.isEmpty() && !"null".equalsIgnoreCase(text)) return text;
            }
        }
        return "";
    }

    private static boolean looksUrl(String value) {
        if (value == null) return false;
        String lower = value.trim().toLowerCase(java.util.Locale.US);
        return lower.startsWith("http://") || lower.startsWith("https://");
    }

    private static String normalizeType(String value) {
        String lower = value.toLowerCase(java.util.Locale.US);
        if (lower.contains("live") || lower.contains("channel") || lower.equals("1")) return "TV en vivo";
        if (lower.contains("movie") || lower.contains("film") || lower.equals("2")) return "Películas";
        if (lower.contains("series") || lower.contains("serie") || lower.contains("tvshow") || lower.equals("3")) return "Series";
        return "Catálogo";
    }
}
