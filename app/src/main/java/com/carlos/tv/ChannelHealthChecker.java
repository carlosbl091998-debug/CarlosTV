package com.carlos.tv;

import java.io.IOException;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.CancellationException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.RejectedExecutionException;

public final class ChannelHealthChecker {

    public interface Callback {
        void onFinished(Set<String> failedUrls);
    }

    private static final int MAX_CHECKS = 120;
    private static final int CONNECT_TIMEOUT_MS = 3_500;
    private static final int READ_TIMEOUT_MS = 3_500;

    private final ExecutorService coordinator = Executors.newSingleThreadExecutor();
    private final ExecutorService probes = Executors.newFixedThreadPool(6);
    private volatile boolean stopped;

    public void check(List<Channel> channels, Callback callback) {
        if (stopped) {
            return;
        }

        List<Channel> snapshot = new ArrayList<>(
                channels.subList(0, Math.min(MAX_CHECKS, channels.size())));
        try {
            coordinator.execute(() -> runChecks(snapshot, callback));
        } catch (RejectedExecutionException ignored) {
            // La actividad ya se está cerrando.
        }
    }

    private void runChecks(List<Channel> channels, Callback callback) {
        List<Future<String>> results = new ArrayList<>();
        for (Channel channel : channels) {
            results.add(probes.submit(() -> findDefinitiveFailure(channel.getStreamUrl())));
        }

        Set<String> failedUrls = new HashSet<>();
        for (Future<String> result : results) {
            if (stopped) {
                return;
            }
            try {
                String failedUrl = result.get();
                if (failedUrl != null) {
                    failedUrls.add(failedUrl);
                }
            } catch (CancellationException ignored) {
                return;
            } catch (Exception ignored) {
                // Un tiempo de espera no prueba que el canal esté caído; se conserva.
            }
        }

        if (!stopped) {
            callback.onFinished(failedUrls);
        }
    }

    private String findDefinitiveFailure(String address) {
        HttpURLConnection connection = null;
        try {
            connection = (HttpURLConnection) new URL(address).openConnection();
            connection.setRequestMethod("GET");
            connection.setConnectTimeout(CONNECT_TIMEOUT_MS);
            connection.setReadTimeout(READ_TIMEOUT_MS);
            connection.setInstanceFollowRedirects(true);
            connection.setRequestProperty("User-Agent", "CarlosTV/0.4 Android");
            connection.setRequestProperty(
                    "Accept",
                    "application/vnd.apple.mpegurl, application/x-mpegURL, video/*, */*");

            int status = connection.getResponseCode();
            if (status == HttpURLConnection.HTTP_BAD_REQUEST
                    || status == HttpURLConnection.HTTP_UNAUTHORIZED
                    || status == HttpURLConnection.HTTP_FORBIDDEN
                    || status == HttpURLConnection.HTTP_NOT_FOUND
                    || status == HttpURLConnection.HTTP_GONE) {
                return address;
            }
        } catch (IOException | ClassCastException ignored) {
            // Fallos de red temporales se consideran desconocidos, no canales muertos.
        } finally {
            if (connection != null) {
                connection.disconnect();
            }
        }
        return null;
    }

    public void shutdown() {
        stopped = true;
        coordinator.shutdownNow();
        probes.shutdownNow();
    }
}
