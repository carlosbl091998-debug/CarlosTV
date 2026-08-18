package com.carlos.tv;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

public final class PublicCatalogRepository {
    private static final String IPTV_CHANNELS = "https://iptv-org.github.io/api/channels.json";
    private static final String IPTV_STREAMS = "https://iptv-org.github.io/api/streams.json";
    private static final String ARCHIVE_SEARCH = "https://archive.org/advancedsearch.php";
    private static final String ARCHIVE_METADATA = "https://archive.org/metadata/";

    private List<XuperProgram> liveCache;
    private List<XuperProgram> moviesCache;
    private List<XuperProgram> seriesCache;

    public synchronized List<XuperProgram> getLiveMexico() throws Exception {
        if (liveCache != null) return new ArrayList<>(liveCache);

        JSONArray channels = new JSONArray(get(IPTV_CHANNELS));
        Map<String, XuperProgram> mx = new HashMap<>();
        for (int i = 0; i < channels.length(); i++) {
            JSONObject c = channels.getJSONObject(i);
            if (!"MX".equalsIgnoreCase(c.optString("country"))) continue;
            if (c.optBoolean("is_nsfw", false)) continue;
            String id = c.optString("id");
            String name = c.optString("name", id);
            String category = "TV México";
            JSONArray cats = c.optJSONArray("categories");
            if (cats != null && cats.length() > 0) category = "TV México · " + cats.optString(0, "General");
            mx.put(id, new XuperProgram(id, name, category, "", "MX", new ArrayList<>()));
        }

        JSONArray streams = new JSONArray(get(IPTV_STREAMS));
        Map<String, List<XuperMedia>> medias = new HashMap<>();
        for (int i = 0; i < streams.length(); i++) {
            JSONObject s = streams.getJSONObject(i);
            String channel = s.optString("channel");
            if (!mx.containsKey(channel)) continue;
            if (!s.isNull("referrer") && !s.optString("referrer").isEmpty()) continue;
            if (!s.isNull("user_agent") && !s.optString("user_agent").isEmpty()) continue;
            String url = s.optString("url");
            if (!(url.startsWith("http://") || url.startsWith("https://"))) continue;
            String q = s.optString("quality", "auto");
            String type = url.toLowerCase(Locale.ROOT).contains(".mpd") ? "dash" : "hls";
            medias.computeIfAbsent(channel, k -> new ArrayList<>()).add(new XuperMedia(url, q, type));
        }

        List<XuperProgram> out = new ArrayList<>();
        for (Map.Entry<String, XuperProgram> e : mx.entrySet()) {
            List<XuperMedia> m = medias.get(e.getKey());
            if (m == null || m.isEmpty()) continue;
            XuperProgram p = e.getValue();
            out.add(new XuperProgram(p.getId(), p.getName(), p.getCategory(), p.getPosterUrl(), p.getCountry(), m));
        }
        out.sort((a,b) -> a.getName().compareToIgnoreCase(b.getName()));
        liveCache = out;
        return new ArrayList<>(out);
    }

    public synchronized List<XuperProgram> getMovies() throws Exception {
        if (moviesCache != null) return new ArrayList<>(moviesCache);
        moviesCache = archiveSearch("mediatype:movies AND language:Spanish", "Película · Internet Archive", 60);
        return new ArrayList<>(moviesCache);
    }

    public synchronized List<XuperProgram> getSeries() throws Exception {
        if (seriesCache != null) return new ArrayList<>(seriesCache);
        seriesCache = archiveSearch("mediatype:movies AND language:Spanish AND (subject:series OR subject:serial OR subject:episodio)", "Serie / episodio · Internet Archive", 40);
        return new ArrayList<>(seriesCache);
    }

    public List<XuperProgram> getHome() throws Exception {
        List<XuperProgram> out = new ArrayList<>();
        List<XuperProgram> live = getLiveMexico();
        List<XuperProgram> movies = getMovies();
        out.addAll(live.subList(0, Math.min(18, live.size())));
        out.addAll(movies.subList(0, Math.min(18, movies.size())));
        return out;
    }

    public XuperProgram resolveArchiveProgram(XuperProgram program) throws Exception {
        if (!program.getId().startsWith("ia:")) return program;
        String identifier = program.getId().substring(3);
        JSONObject root = new JSONObject(get(ARCHIVE_METADATA + encodePath(identifier)));
        JSONArray files = root.optJSONArray("files");
        List<XuperMedia> media = new ArrayList<>();
        if (files != null) {
            for (int i = 0; i < files.length(); i++) {
                JSONObject f = files.getJSONObject(i);
                String name = f.optString("name");
                String lower = name.toLowerCase(Locale.ROOT);
                String format = f.optString("format").toLowerCase(Locale.ROOT);
                boolean playable = lower.endsWith(".mp4") || lower.endsWith(".m4v") || lower.endsWith(".ogv") || format.contains("h.264") || format.contains("mpeg4");
                if (!playable) continue;
                String url = "https://archive.org/download/" + encodePath(identifier) + "/" + encodePathSegments(name);
                media.add(new XuperMedia(url, format.contains("512") ? "SD" : "auto", "file"));
                if (media.size() >= 4) break;
            }
        }
        String poster = "https://archive.org/services/img/" + encodePath(identifier);
        return new XuperProgram(program.getId(), program.getName(), program.getCategory(), poster, program.getCountry(), media);
    }

    private List<XuperProgram> archiveSearch(String query, String category, int rows) throws Exception {
        String url = ARCHIVE_SEARCH + "?q=" + URLEncoder.encode(query, StandardCharsets.UTF_8.name())
                + "&fl%5B%5D=identifier&fl%5B%5D=title&fl%5B%5D=year&rows=" + rows + "&page=1&output=json";
        JSONObject root = new JSONObject(get(url));
        JSONArray docs = root.getJSONObject("response").optJSONArray("docs");
        List<XuperProgram> out = new ArrayList<>();
        if (docs == null) return out;
        for (int i = 0; i < docs.length(); i++) {
            JSONObject d = docs.getJSONObject(i);
            String id = d.optString("identifier");
            String title = d.optString("title", id);
            String year = d.opt("year") == null ? "" : String.valueOf(d.opt("year"));
            if (id.isEmpty() || title.isEmpty()) continue;
            String poster = "https://archive.org/services/img/" + encodePath(id);
            String cat = year.isEmpty() ? category : category + " · " + year;
            out.add(new XuperProgram("ia:" + id, title, cat, poster, "ES", new ArrayList<>()));
        }
        return out;
    }

    private String get(String urlText) throws Exception {
        HttpURLConnection conn = (HttpURLConnection) new URL(urlText).openConnection();
        conn.setConnectTimeout(10000);
        conn.setReadTimeout(20000);
        conn.setRequestProperty("Accept", "application/json");
        conn.setRequestProperty("User-Agent", "CarlosTV/0.8 Android");
        try (BufferedReader r = new BufferedReader(new InputStreamReader(conn.getInputStream(), StandardCharsets.UTF_8))) {
            StringBuilder b = new StringBuilder();
            char[] buf = new char[8192];
            int n;
            while ((n = r.read(buf)) >= 0) b.append(buf, 0, n);
            return b.toString();
        } finally {
            conn.disconnect();
        }
    }

    private static String encodePath(String s) {
        return URLEncoder.encode(s, StandardCharsets.UTF_8).replace("+", "%20").replace("%2F", "/");
    }

    private static String encodePathSegments(String s) {
        String[] parts = s.split("/");
        StringBuilder b = new StringBuilder();
        for (int i = 0; i < parts.length; i++) {
            if (i > 0) b.append('/');
            b.append(URLEncoder.encode(parts[i], StandardCharsets.UTF_8).replace("+", "%20"));
        }
        return b.toString();
    }
}
