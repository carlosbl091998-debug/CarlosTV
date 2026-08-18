package com.carlos.tv;

import android.content.Context;

import java.io.InputStream;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

public final class LocalCatalogRepository {
    private final Context context;

    public LocalCatalogRepository(Context context) {
        this.context = context.getApplicationContext();
    }

    public List<XuperProgram> getLive() throws Exception {
        try (InputStream in = context.getAssets().open("mexico_tv.m3u")) {
            M3uParser.ParseResult result = new M3uParser().parse(in);
            List<XuperProgram> out = new ArrayList<>();
            int i = 0;
            for (Channel c : result.getChannels()) {
                List<XuperMedia> medias = new ArrayList<>();
                medias.add(new XuperMedia(c.getStreamUrl(), "AUTO", "hls"));
                out.add(new XuperProgram("live:" + (++i), c.getName(), c.getCategory(), c.getLogoUrl(), "MX", medias));
            }
            return out;
        }
    }

    public List<XuperProgram> getMovies() {
        List<XuperProgram> out = new ArrayList<>();
        out.add(video("movie:1", "Cine Demo HD", "Películas · Demo", "https://storage.googleapis.com/gtv-videos-bucket/sample/images/BigBuckBunny.jpg", "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8", "hls"));
        out.add(video("movie:2", "Cortometraje Demo", "Películas · Demo", "https://storage.googleapis.com/gtv-videos-bucket/sample/images/ElephantsDream.jpg", "https://storage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4", "mp4"));
        out.add(video("movie:3", "Acción Demo", "Películas · Demo", "https://storage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerBlazes.jpg", "https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4", "mp4"));
        out.add(video("movie:4", "Aventura Demo", "Películas · Demo", "https://storage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerEscapes.jpg", "https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4", "mp4"));
        return out;
    }

    public List<XuperProgram> getSeries() {
        List<XuperProgram> out = new ArrayList<>();
        out.add(video("series:1", "Serie Demo · Episodio 1", "Series · Temporada 1", "https://storage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerFun.jpg", "https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4", "mp4"));
        out.add(video("series:2", "Serie Demo · Episodio 2", "Series · Temporada 1", "https://storage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerJoyrides.jpg", "https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyrides.mp4", "mp4"));
        out.add(video("series:3", "Serie Demo · Episodio 3", "Series · Temporada 1", "https://storage.googleapis.com/gtv-videos-bucket/sample/images/Sintel.jpg", "https://storage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4", "mp4"));
        return out;
    }

    public List<XuperProgram> getHome() throws Exception {
        List<XuperProgram> out = new ArrayList<>();
        List<XuperProgram> live = getLive();
        List<XuperProgram> movies = getMovies();
        List<XuperProgram> series = getSeries();
        out.addAll(live.subList(0, Math.min(12, live.size())));
        out.addAll(movies);
        out.addAll(series);
        return out;
    }

    private XuperProgram video(String id, String name, String category, String poster, String url, String type) {
        List<XuperMedia> medias = new ArrayList<>();
        medias.add(new XuperMedia(url, "AUTO", type));
        return new XuperProgram(id, name, category, poster, "", Collections.unmodifiableList(medias));
    }
}
