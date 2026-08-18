package com.carlos.tv;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.util.LruCache;
import android.view.View;
import android.widget.ImageView;
import android.widget.TextView;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class LogoLoader {

    private static final int MAX_LOGO_BYTES = 2 * 1024 * 1024;

    private final ExecutorService executor = Executors.newFixedThreadPool(3);
    private final LruCache<String, Bitmap> cache =
            new LruCache<String, Bitmap>(4 * 1024 * 1024) {
                @Override
                protected int sizeOf(String key, Bitmap value) {
                    return value.getByteCount();
                }
            };

    public void load(String address, ImageView image, TextView fallback, String initial) {
        image.setTag(address);
        image.setImageDrawable(null);
        image.setVisibility(View.GONE);
        fallback.setText(initial);
        fallback.setVisibility(View.VISIBLE);

        if (!isSupportedAddress(address)) {
            return;
        }

        Bitmap cached = cache.get(address);
        if (cached != null) {
            showIfCurrent(address, image, fallback, cached);
            return;
        }

        executor.execute(() -> {
            Bitmap bitmap = download(address);
            if (bitmap != null) {
                cache.put(address, bitmap);
                image.post(() -> showIfCurrent(address, image, fallback, bitmap));
            }
        });
    }

    private boolean isSupportedAddress(String address) {
        if (address == null || address.trim().isEmpty()) {
            return false;
        }
        String lower = address.toLowerCase(Locale.US);
        return (lower.startsWith("https://") || lower.startsWith("http://"))
                && !lower.contains(".svg");
    }

    private Bitmap download(String address) {
        HttpURLConnection connection = null;
        try {
            connection = (HttpURLConnection) new URL(address).openConnection();
            connection.setConnectTimeout(5_000);
            connection.setReadTimeout(7_000);
            connection.setInstanceFollowRedirects(true);
            connection.setRequestProperty("User-Agent", "CarlosTV/0.3 Android");

            int status = connection.getResponseCode();
            if (status < 200 || status >= 300) {
                return null;
            }

            try (InputStream input = connection.getInputStream();
                 ByteArrayOutputStream output = new ByteArrayOutputStream()) {
                byte[] buffer = new byte[8 * 1024];
                int total = 0;
                int read;
                while ((read = input.read(buffer)) != -1) {
                    total += read;
                    if (total > MAX_LOGO_BYTES) {
                        return null;
                    }
                    output.write(buffer, 0, read);
                }

                byte[] bytes = output.toByteArray();
                Bitmap bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.length);
                if (bitmap == null) {
                    return null;
                }
                int largest = Math.max(bitmap.getWidth(), bitmap.getHeight());
                if (largest > 256) {
                    float scale = 256f / largest;
                    return Bitmap.createScaledBitmap(
                            bitmap,
                            Math.max(1, Math.round(bitmap.getWidth() * scale)),
                            Math.max(1, Math.round(bitmap.getHeight() * scale)),
                            true);
                }
                return bitmap;
            }
        } catch (Exception ignored) {
            return null;
        } finally {
            if (connection != null) {
                connection.disconnect();
            }
        }
    }

    private void showIfCurrent(
            String address,
            ImageView image,
            TextView fallback,
            Bitmap bitmap) {
        if (!address.equals(image.getTag())) {
            return;
        }
        image.setImageBitmap(bitmap);
        image.setVisibility(View.VISIBLE);
        fallback.setVisibility(View.GONE);
    }

    public void shutdown() {
        executor.shutdownNow();
    }
}
