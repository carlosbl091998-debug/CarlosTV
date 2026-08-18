package com.carlos.tv;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

public final class XtreamClient {
    private String baseUrl = "";
    private String rawServer = "";
    private String username = "";
    private String password = "";

    public void configure(String server, String user, String pass) {
        String s = server == null ? "" : server.trim();
        while (s.endsWith("/")) s = s.substring(0, s.length() - 1);
        rawServer = s;
        baseUrl = normalizePreferred(s);
        username = user == null ? "" : user.trim();
        password = pass == null ? "" : pass;
    }

    public boolean isConfigured() {
        return !rawServer.isEmpty() && !username.isEmpty() && !password.isEmpty();
    }

    public AuthResult authenticate() throws Exception {
        if (!isConfigured()) return new AuthResult(false, "Faltan datos del portal", "");

        List<String> candidates = candidateBases(rawServer);
        StringBuilder diagnostics = new StringBuilder();

        for (String candidate : candidates) {
            HttpResult response;
            try {
                response = request(apiUrlFor(candidate, null));
            } catch (Exception e) {
                appendDiagnostic(diagnostics, candidate, e.getClass().getSimpleName());
                continue;
            }

            if (response.code == 401 || response.code == 403) {
                return new AuthResult(false, "El servidor rechazó las credenciales (HTTP " + response.code + ")", candidate);
            }
            if (response.code < 200 || response.code >= 300) {
                appendDiagnostic(diagnostics, candidate, "HTTP " + response.code);
                continue;
            }

            try {
                JSONObject root = new JSONObject(response.body);
                JSONObject userInfo = root.optJSONObject("user_info");
                JSONObject serverInfo = root.optJSONObject("server_info");
                if (userInfo == null) {
                    appendDiagnostic(diagnostics, candidate, "respuesta sin user_info");
                    continue;
                }

                boolean ok = "1".equals(String.valueOf(userInfo.opt("auth")));
                if (!ok) {
                    return new AuthResult(false, "Acceso rechazado por el portal", candidate);
                }

                baseUrl = candidate;
                String status = userInfo.optString("status", "Active");
                String serverName = serverInfo == null ? candidate : serverInfo.optString("url", candidate);
                return new AuthResult(true, status + " · " + candidate, serverName);
            } catch (Exception jsonError) {
                appendDiagnostic(diagnostics, candidate, "respuesta no JSON");
            }
        }

        throw new IllegalStateException("No encontramos un endpoint Xtream estándar. " + diagnostics);
    }

    public List<XuperProgram> getLive() throws Exception {
        JSONArray arr = new JSONArray(get(apiUrl("get_live_streams")));
        List<XuperProgram> out = new ArrayList<>();
        for (int i = 0; i < arr.length(); i++) {
            JSONObject o = arr.optJSONObject(i);
            if (o == null) continue;
            String id = String.valueOf(o.opt("stream_id"));
            String name = o.optString("name", "Canal");
            String icon = o.optString("stream_icon", "");
            String cat = o.optString("category_id", "TV");
            String ext = cleanExt(o.optString("container_extension", "m3u8"), "m3u8");
            String direct = o.optString("direct_source", "");
            String url = playableOr(direct, baseUrl + "/live/" + encPath(username) + "/" + encPath(password) + "/" + id + "." + ext);
            out.add(program("live:" + id, name, "TV · " + cat, icon, url, ext));
        }
        return out;
    }

    public List<XuperProgram> getMovies() throws Exception {
        JSONArray arr = new JSONArray(get(apiUrl("get_vod_streams")));
        List<XuperProgram> out = new ArrayList<>();
        for (int i = 0; i < arr.length(); i++) {
            JSONObject o = arr.optJSONObject(i);
            if (o == null) continue;
            String id = String.valueOf(o.opt("stream_id"));
            String name = o.optString("name", "Película");
            String icon = o.optString("stream_icon", "");
            String cat = o.optString("category_id", "VOD");
            String ext = cleanExt(o.optString("container_extension", "mp4"), "mp4");
            String direct = o.optString("direct_source", "");
            String url = playableOr(direct, baseUrl + "/movie/" + encPath(username) + "/" + encPath(password) + "/" + id + "." + ext);
            out.add(program("movie:" + id, name, "Película · " + cat, icon, url, ext));
        }
        return out;
    }

    public List<XuperProgram> getSeries() throws Exception {
        JSONArray arr = new JSONArray(get(apiUrl("get_series")));
        List<XuperProgram> out = new ArrayList<>();
        for (int i = 0; i < arr.length(); i++) {
            JSONObject o = arr.optJSONObject(i);
            if (o == null) continue;
            String id = String.valueOf(o.opt("series_id"));
            String name = o.optString("name", "Serie");
            String cover = o.optString("cover", "");
            String cat = o.optString("category_id", "Series");
            out.add(new XuperProgram("series:" + id, name, "Serie · " + cat, cover, "", Collections.emptyList()));
        }
        return out;
    }

    public XuperProgram resolveSeriesFirstEpisode(XuperProgram series) throws Exception {
        String raw = series.getId().startsWith("series:") ? series.getId().substring(7) : series.getId();
        JSONObject root = new JSONObject(get(apiUrlWith("get_series_info", "series_id", raw)));
        JSONObject episodes = root.optJSONObject("episodes");
        if (episodes == null) return series;
        for (String season : keysSorted(episodes)) {
            JSONArray list = episodes.optJSONArray(season);
            if (list == null || list.length() == 0) continue;
            JSONObject ep = list.optJSONObject(0);
            if (ep == null) continue;
            String id = String.valueOf(ep.opt("id"));
            String ext = cleanExt(ep.optString("container_extension", "mp4"), "mp4");
            String direct = ep.optString("direct_source", "");
            String url = playableOr(direct, baseUrl + "/series/" + encPath(username) + "/" + encPath(password) + "/" + id + "." + ext);
            String title = ep.optString("title", series.getName());
            List<XuperMedia> medias = new ArrayList<>();
            medias.add(new XuperMedia(url, "AUTO", ext));
            return new XuperProgram(series.getId(), series.getName() + " · " + title, "Serie", series.getPosterUrl(), "", medias);
        }
        return series;
    }

    private XuperProgram program(String id, String name, String category, String poster, String url, String ext) {
        List<XuperMedia> medias = new ArrayList<>();
        medias.add(new XuperMedia(url, "AUTO", ext));
        return new XuperProgram(id, name, category, poster, "", medias);
    }

    private String apiUrl(String action) throws Exception {
        return apiUrlFor(baseUrl, action);
    }

    private String apiUrlFor(String base, String action) throws Exception {
        String url = base + "/player_api.php?username=" + enc(username) + "&password=" + enc(password);
        if (action != null && !action.isEmpty()) url += "&action=" + enc(action);
        return url;
    }

    private String apiUrlWith(String action, String key, String value) throws Exception {
        return apiUrl(action) + "&" + enc(key) + "=" + enc(value);
    }

    private String get(String url) throws Exception {
        HttpResult response = request(url);
        if (response.code < 200 || response.code >= 300) {
            throw new IllegalStateException("HTTP " + response.code);
        }
        return response.body;
    }

    private HttpResult request(String url) throws Exception {
        HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
        c.setInstanceFollowRedirects(true);
        c.setConnectTimeout(12000);
        c.setReadTimeout(20000);
        c.setRequestMethod("GET");
        c.setRequestProperty("Accept", "application/json, text/plain, */*");
        c.setRequestProperty("User-Agent", "CarlosTV/1.0.1 Android");
        int code = c.getResponseCode();
        InputStream in = code >= 200 && code < 300 ? c.getInputStream() : c.getErrorStream();
        String body = "";
        if (in != null) {
            BufferedReader r = new BufferedReader(new InputStreamReader(in, StandardCharsets.UTF_8));
            StringBuilder b = new StringBuilder();
            String line;
            while ((line = r.readLine()) != null) b.append(line);
            r.close();
            body = b.toString();
        }
        c.disconnect();
        return new HttpResult(code, body);
    }

    private static List<String> candidateBases(String raw) {
        List<String> out = new ArrayList<>();
        String s = raw == null ? "" : raw.trim();
        while (s.endsWith("/")) s = s.substring(0, s.length() - 1);
        if (s.startsWith("https://") || s.startsWith("http://")) {
            out.add(s);
            return out;
        }
        out.add("https://" + s);
        out.add("http://" + s);
        return out;
    }

    private static String normalizePreferred(String raw) {
        if (raw == null || raw.trim().isEmpty()) return "";
        String s = raw.trim();
        while (s.endsWith("/")) s = s.substring(0, s.length() - 1);
        if (s.startsWith("https://") || s.startsWith("http://")) return s;
        return "https://" + s;
    }

    private static void appendDiagnostic(StringBuilder diagnostics, String candidate, String message) {
        if (diagnostics.length() > 0) diagnostics.append(" | ");
        diagnostics.append(candidate).append(": ").append(message);
    }

    private static String enc(String s) throws Exception {
        return URLEncoder.encode(s, "UTF-8");
    }

    private static String encPath(String s) {
        return s.replace("/", "%2F").replace(" ", "%20");
    }

    private static String playableOr(String direct, String fallback) {
        if (direct != null && (direct.startsWith("http://") || direct.startsWith("https://"))) return direct;
        return fallback;
    }

    private static String cleanExt(String ext, String fallback) {
        if (ext == null || ext.trim().isEmpty()) return fallback;
        return ext.replace(".", "").trim();
    }

    private static List<String> keysSorted(JSONObject o) {
        List<String> keys = new ArrayList<>();
        java.util.Iterator<String> it = o.keys();
        while (it.hasNext()) keys.add(it.next());
        Collections.sort(keys);
        return keys;
    }

    private static final class HttpResult {
        final int code;
        final String body;
        HttpResult(int code, String body) {
            this.code = code;
            this.body = body == null ? "" : body;
        }
    }

    public static final class AuthResult {
        public final boolean ok;
        public final String status;
        public final String serverName;
        public AuthResult(boolean ok, String status, String serverName) {
            this.ok = ok;
            this.status = status;
            this.serverName = serverName;
        }
    }
}
