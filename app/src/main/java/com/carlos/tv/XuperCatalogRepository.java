package com.carlos.tv;

import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.List;

/**
 * Cliente HTTP mínimo para el backend de referencia. La sesión se inyecta en tiempo de ejecución;
 * no se almacenan credenciales dentro del código fuente.
 */
public final class XuperCatalogRepository {
    private static final int CONNECT_TIMEOUT_MS = 7_000;
    private static final int READ_TIMEOUT_MS = 12_000;
    private static final int MAX_RESPONSE_CHARS = 12_000_000;

    private final XuperCatalogParser parser = new XuperCatalogParser();
    private String baseUrl;
    private String userToken = "";
    private String userId = "";
    private String portalCode = "";

    public XuperCatalogRepository(String baseUrl) {
        this.baseUrl = baseUrl == null || baseUrl.trim().isEmpty()
                ? XuperContract.DEFAULT_BASE_URL : baseUrl.trim();
    }

    public void setSession(String userToken, String userId, String portalCode) {
        this.userToken = clean(userToken);
        this.userId = clean(userId);
        this.portalCode = clean(portalCode);
    }

    public boolean hasSession() {
        return !userToken.isEmpty() && !userId.isEmpty();
    }

    public List<XuperProgram> getColumnContents(int columnId, int pageNum, int pageSize)
            throws Exception {
        JSONObject body = baseBody();
        body.put("columnId", columnId);
        body.put("specialFlag", "0");
        body.put("pageNum", pageNum);
        body.put("pageSize", pageSize);
        body.put("numDisplay", pageSize);
        return parser.parse(postJson(XuperContract.GET_COLUMN_CONTENTS, body));
    }

    public List<XuperProgram> getHomeCatalog() throws Exception {
        return parser.parse(postJson(XuperContract.GET_HOME, baseBody()));
    }

    public List<XuperProgram> getLiveCatalog() throws Exception {
        try {
            return parser.parse(postJson(XuperContract.GET_LIVE_DATA_V7, baseBody()));
        } catch (IOException first) {
            return parser.parse(postJson(XuperContract.GET_LIVE_DATA_V5, baseBody()));
        }
    }

    public List<XuperProgram> getProgram(String programId) throws Exception {
        JSONObject body = baseBody();
        body.put("programId", programId);
        body.put("contentId", programId);
        return parser.parse(postJson(XuperContract.GET_PROGRAM, body));
    }

    private JSONObject baseBody() throws Exception {
        JSONObject body = new JSONObject();
        if (!userToken.isEmpty()) body.put("userToken", userToken);
        if (!userId.isEmpty()) body.put("userId", userId);
        if (!portalCode.isEmpty()) body.put("portalCode", portalCode);
        return body;
    }

    private String postJson(String path, JSONObject body) throws IOException {
        HttpURLConnection connection = null;
        try {
            connection = (HttpURLConnection) new URL(XuperContract.absolute(baseUrl, path)).openConnection();
            connection.setRequestMethod("POST");
            connection.setConnectTimeout(CONNECT_TIMEOUT_MS);
            connection.setReadTimeout(READ_TIMEOUT_MS);
            connection.setInstanceFollowRedirects(true);
            connection.setDoOutput(true);
            connection.setRequestProperty("Content-Type", "application/json; charset=UTF-8");
            connection.setRequestProperty("Accept", "application/json");
            connection.setRequestProperty("User-Agent", "CarlosTV/0.6 Android");
            byte[] payload = body.toString().getBytes(StandardCharsets.UTF_8);
            connection.setFixedLengthStreamingMode(payload.length);
            try (OutputStream out = connection.getOutputStream()) {
                out.write(payload);
            }

            int status = connection.getResponseCode();
            InputStream stream = status >= 200 && status < 300
                    ? connection.getInputStream() : connection.getErrorStream();
            String response = readLimited(stream);
            if (status < 200 || status >= 300) {
                throw new IOException("Backend Xuper respondió HTTP " + status);
            }
            if (response.trim().isEmpty()) {
                throw new IOException("Backend Xuper devolvió una respuesta vacía");
            }
            return response;
        } finally {
            if (connection != null) connection.disconnect();
        }
    }

    private static String readLimited(InputStream input) throws IOException {
        if (input == null) return "";
        StringBuilder result = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(input, StandardCharsets.UTF_8))) {
            char[] buffer = new char[8192];
            int read;
            while ((read = reader.read(buffer)) != -1) {
                result.append(buffer, 0, read);
                if (result.length() > MAX_RESPONSE_CHARS) {
                    throw new IOException("Respuesta de catálogo demasiado grande");
                }
            }
        }
        return result.toString();
    }

    private static String clean(String value) {
        return value == null ? "" : value.trim();
    }
}
