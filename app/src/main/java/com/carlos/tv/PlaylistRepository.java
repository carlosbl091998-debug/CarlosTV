package com.carlos.tv;

import android.content.ContentResolver;
import android.content.Context;
import android.database.Cursor;
import android.net.Uri;
import android.provider.OpenableColumns;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.List;

public final class PlaylistRepository {

    public static final String DEFAULT_PLAYLIST_URL =
            "https://iptv-org.github.io/iptv/index.m3u";

    private static final int MAX_PLAYLIST_BYTES = 30 * 1024 * 1024;
    private static final long CACHE_MAX_AGE_MS = 6L * 60L * 60L * 1000L;
    private static final String CACHE_FILE_NAME = "iptv_org_channels.m3u";

    private final Context context;
    private final M3uParser parser = new M3uParser();

    public PlaylistRepository(Context context) {
        this.context = context.getApplicationContext();
    }

    public LoadResult loadDefault(boolean forceRefresh) throws IOException {
        File cacheFile = new File(context.getFilesDir(), CACHE_FILE_NAME);
        boolean cacheFresh = cacheFile.isFile()
                && System.currentTimeMillis() - cacheFile.lastModified() < CACHE_MAX_AGE_MS;

        if (!forceRefresh && cacheFresh) {
            return parseFile(cacheFile, "IPTV-org · guardada", true);
        }

        try {
            byte[] bytes = download(DEFAULT_PLAYLIST_URL);
            M3uParser.ParseResult parsed = parser.parse(new ByteArrayInputStream(bytes));
            writeCache(cacheFile, bytes);
            return new LoadResult(
                    parsed.getChannels(),
                    parsed.getSkipped(),
                    "IPTV-org",
                    false);
        } catch (IOException networkError) {
            if (cacheFile.isFile()) {
                return parseFile(cacheFile, "IPTV-org · sin conexión", true);
            }
            throw networkError;
        }
    }

    public LoadResult loadFromDocument(Uri uri) throws IOException {
        ContentResolver resolver = context.getContentResolver();
        try (InputStream input = resolver.openInputStream(uri)) {
            if (input == null) {
                throw new IOException("No se pudo abrir el archivo seleccionado.");
            }
            M3uParser.ParseResult parsed = parser.parse(input);
            return new LoadResult(
                    parsed.getChannels(),
                    parsed.getSkipped(),
                    getDisplayName(resolver, uri),
                    false);
        }
    }

    private LoadResult parseFile(File file, String sourceName, boolean fromCache)
            throws IOException {
        try (InputStream input = new FileInputStream(file)) {
            M3uParser.ParseResult parsed = parser.parse(input);
            return new LoadResult(
                    parsed.getChannels(),
                    parsed.getSkipped(),
                    sourceName,
                    fromCache);
        }
    }

    private byte[] download(String address) throws IOException {
        HttpURLConnection connection = null;
        try {
            connection = (HttpURLConnection) new URL(address).openConnection();
            connection.setConnectTimeout(12_000);
            connection.setReadTimeout(25_000);
            connection.setInstanceFollowRedirects(true);
            connection.setRequestProperty("User-Agent", "CarlosTV/0.3 Android");
            connection.setRequestProperty(
                    "Accept",
                    "application/x-mpegURL, application/vnd.apple.mpegurl, text/plain, */*");

            int status = connection.getResponseCode();
            if (status < 200 || status >= 300) {
                throw new IOException("El servidor respondió con el código " + status + ".");
            }

            try (InputStream input = connection.getInputStream()) {
                return readLimited(input);
            }
        } finally {
            if (connection != null) {
                connection.disconnect();
            }
        }
    }

    private byte[] readLimited(InputStream input) throws IOException {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] buffer = new byte[16 * 1024];
        int total = 0;
        int read;
        while ((read = input.read(buffer)) != -1) {
            total += read;
            if (total > MAX_PLAYLIST_BYTES) {
                throw new IOException("La lista supera el límite de 30 MB.");
            }
            output.write(buffer, 0, read);
        }
        return output.toByteArray();
    }

    private void writeCache(File cacheFile, byte[] bytes) {
        File temporary = new File(cacheFile.getParentFile(), cacheFile.getName() + ".tmp");
        try (FileOutputStream output = new FileOutputStream(temporary)) {
            output.write(bytes);
            output.flush();
            if (!temporary.renameTo(cacheFile)) {
                try (FileOutputStream fallback = new FileOutputStream(cacheFile)) {
                    fallback.write(bytes);
                }
            }
        } catch (IOException ignored) {
            // La caché es una mejora opcional; la lista descargada sigue siendo utilizable.
        } finally {
            if (temporary.exists() && !temporary.equals(cacheFile)) {
                //noinspection ResultOfMethodCallIgnored
                temporary.delete();
            }
        }
    }

    private String getDisplayName(ContentResolver resolver, Uri uri) {
        try (Cursor cursor = resolver.query(
                uri,
                new String[]{OpenableColumns.DISPLAY_NAME},
                null,
                null,
                null)) {
            if (cursor != null && cursor.moveToFirst()) {
                int index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                if (index >= 0) {
                    String value = cursor.getString(index);
                    if (value != null && !value.trim().isEmpty()) {
                        return value.trim();
                    }
                }
            }
        } catch (RuntimeException ignored) {
            // Se mostrará un nombre genérico si el proveedor no comparte metadatos.
        }
        return "Mi lista M3U";
    }

    public static final class LoadResult {
        private final List<Channel> channels;
        private final int skipped;
        private final String sourceName;
        private final boolean fromCache;

        private LoadResult(
                List<Channel> channels,
                int skipped,
                String sourceName,
                boolean fromCache) {
            this.channels = channels;
            this.skipped = skipped;
            this.sourceName = sourceName;
            this.fromCache = fromCache;
        }

        public List<Channel> getChannels() {
            return channels;
        }

        public int getSkipped() {
            return skipped;
        }

        public String getSourceName() {
            return sourceName;
        }

        public boolean isFromCache() {
            return fromCache;
        }
    }
}
