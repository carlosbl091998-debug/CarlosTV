package com.carlos.tv;

import android.content.Context;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

public final class PlaylistRepository {

    private static final SourceSpec[] SOURCES = new SourceSpec[]{
            new SourceSpec(
                    "M3U.CL México",
                    "https://www.m3u.cl/lista/MX.m3u",
                    "m3u_cl_mexico.m3u",
                    true),
            new SourceSpec(
                    "PL Pro",
                    "http://pl.pro/lista.m3u",
                    "pl_pro.m3u",
                    false)
    };

    private static final int MAX_PLAYLIST_BYTES = 30 * 1024 * 1024;
    private static final long CACHE_MAX_AGE_MS = 6L * 60L * 60L * 1000L;

    private final Context context;
    private final M3uParser parser = new M3uParser();

    public PlaylistRepository(Context context) {
        this.context = context.getApplicationContext();
    }

    public LoadResult loadDefault(boolean forceRefresh) throws IOException {
        List<Channel> merged = new ArrayList<>();
        Set<String> seenStreams = new HashSet<>();
        List<String> loadedSources = new ArrayList<>();
        List<String> failedSources = new ArrayList<>();
        int skipped = 0;
        boolean onlyCache = true;

        for (SourceSpec source : SOURCES) {
            try {
                SourceResult sourceResult = loadSource(source, forceRefresh);
                List<Channel> spanishChannels = SpanishChannelFilter.filterAndNormalize(
                        sourceResult.channels,
                        source.assumeSpanish);
                skipped += sourceResult.skipped;
                skipped += Math.max(0, sourceResult.channels.size() - spanishChannels.size());

                int beforeMerge = merged.size();
                for (Channel channel : spanishChannels) {
                    if (seenStreams.add(channel.getStreamUrl())) {
                        merged.add(channel);
                    } else {
                        skipped++;
                    }
                }

                if (merged.size() > beforeMerge) {
                    loadedSources.add(source.name);
                    onlyCache &= sourceResult.fromCache;
                }
            } catch (IOException sourceError) {
                failedSources.add(source.name);
            }
        }

        if (merged.isEmpty()) {
            throw new IOException(
                    "No se pudo cargar ninguna fuente de canales en español. Inténtalo nuevamente.");
        }

        String sourceName = joinSources(loadedSources);
        if (!failedSources.isEmpty()) {
            sourceName += " · " + failedSources.size()
                    + (failedSources.size() == 1
                    ? " fuente sin conexión"
                    : " fuentes sin conexión");
        }

        return new LoadResult(merged, skipped, sourceName, onlyCache);
    }

    private SourceResult loadSource(SourceSpec source, boolean forceRefresh) throws IOException {
        File cacheFile = new File(context.getFilesDir(), source.cacheFileName);
        boolean cacheFresh = cacheFile.isFile()
                && System.currentTimeMillis() - cacheFile.lastModified() < CACHE_MAX_AGE_MS;

        if (!forceRefresh && cacheFresh) {
            return parseFile(cacheFile, true);
        }

        try {
            byte[] bytes = download(source.url);
            M3uParser.ParseResult parsed = parser.parse(new ByteArrayInputStream(bytes));
            writeCache(cacheFile, bytes);
            return new SourceResult(parsed.getChannels(), parsed.getSkipped(), false);
        } catch (IOException networkError) {
            if (cacheFile.isFile()) {
                return parseFile(cacheFile, true);
            }
            throw networkError;
        }
    }

    private SourceResult parseFile(File file, boolean fromCache) throws IOException {
        try (InputStream input = new FileInputStream(file)) {
            M3uParser.ParseResult parsed = parser.parse(input);
            return new SourceResult(parsed.getChannels(), parsed.getSkipped(), fromCache);
        }
    }

    private byte[] download(String address) throws IOException {
        HttpURLConnection connection = null;
        try {
            connection = (HttpURLConnection) new URL(address).openConnection();
            connection.setConnectTimeout(8_000);
            connection.setReadTimeout(15_000);
            connection.setInstanceFollowRedirects(true);
            connection.setRequestProperty("User-Agent", "CarlosTV/0.4 Android");
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
            // La caché es opcional; la lista descargada sigue siendo utilizable.
        } finally {
            if (temporary.exists() && !temporary.equals(cacheFile)) {
                //noinspection ResultOfMethodCallIgnored
                temporary.delete();
            }
        }
    }

    private static String joinSources(List<String> sources) {
        StringBuilder joined = new StringBuilder();
        for (String source : sources) {
            if (joined.length() > 0) {
                joined.append(" + ");
            }
            joined.append(source);
        }
        return joined.toString();
    }

    private static final class SourceSpec {
        private final String name;
        private final String url;
        private final String cacheFileName;
        private final boolean assumeSpanish;

        private SourceSpec(
                String name,
                String url,
                String cacheFileName,
                boolean assumeSpanish) {
            this.name = name;
            this.url = url;
            this.cacheFileName = cacheFileName;
            this.assumeSpanish = assumeSpanish;
        }
    }

    private static final class SourceResult {
        private final List<Channel> channels;
        private final int skipped;
        private final boolean fromCache;

        private SourceResult(List<Channel> channels, int skipped, boolean fromCache) {
            this.channels = channels;
            this.skipped = skipped;
            this.fromCache = fromCache;
        }
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
