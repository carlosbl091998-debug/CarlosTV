package com.carlos.tv;

import android.app.Activity;
import android.content.pm.ActivityInfo;
import android.os.Bundle;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.View;
import android.view.WindowManager;
import android.widget.EditText;
import android.widget.TextView;
import android.widget.Toast;

import androidx.media3.common.MediaItem;
import androidx.media3.common.MimeTypes;
import androidx.media3.common.PlaybackException;
import androidx.media3.common.Player;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.ui.PlayerView;
import androidx.recyclerview.widget.GridLayoutManager;
import androidx.recyclerview.widget.RecyclerView;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

@UnstableApi
public class MainActivity extends Activity implements ProgramAdapter.Listener {
    private enum Section { HOME, LIVE, MOVIES, SERIES }

    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private final List<XuperProgram> loaded = new ArrayList<>();

    private PublicCatalogRepository repository;
    private ProgramAdapter adapter;
    private EditText searchInput;
    private RecyclerView programList;
    private TextView emptyLabel;
    private TextView sectionTitle;
    private TextView sectionStatus;
    private View loadingPanel;
    private View playerPanel;
    private View playerToolbar;
    private PlayerView playerView;
    private TextView playerTitle;
    private TextView playerStatus;
    private ExoPlayer player;
    private Section section = Section.HOME;
    private boolean fullscreen;
    private int generation;

    @Override protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        repository = new PublicCatalogRepository();
        bindViews();
        configureUi();
        loadSection(Section.HOME);
    }

    private void bindViews() {
        programList = findViewById(R.id.program_list);
        searchInput = findViewById(R.id.search_input);
        emptyLabel = findViewById(R.id.empty_label);
        sectionTitle = findViewById(R.id.section_title);
        sectionStatus = findViewById(R.id.section_status);
        loadingPanel = findViewById(R.id.loading_panel);
        playerPanel = findViewById(R.id.player_panel);
        playerToolbar = findViewById(R.id.player_toolbar);
        playerView = findViewById(R.id.player_view);
        playerTitle = findViewById(R.id.player_title);
        playerStatus = findViewById(R.id.player_status);
    }

    private void configureUi() {
        adapter = new ProgramAdapter(this);
        int columns = getResources().getConfiguration().screenWidthDp >= 700 ? 4 : 2;
        programList.setLayoutManager(new GridLayoutManager(this, columns));
        programList.setAdapter(adapter);
        programList.setHasFixedSize(true);

        findViewById(R.id.tab_home).setOnClickListener(v -> loadSection(Section.HOME));
        findViewById(R.id.tab_live).setOnClickListener(v -> loadSection(Section.LIVE));
        findViewById(R.id.tab_movies).setOnClickListener(v -> loadSection(Section.MOVIES));
        findViewById(R.id.tab_series).setOnClickListener(v -> loadSection(Section.SERIES));
        findViewById(R.id.close_player_button).setOnClickListener(v -> closePlayer());
        findViewById(R.id.fullscreen_button).setOnClickListener(v -> toggleFullscreen());

        searchInput.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
            @Override public void onTextChanged(CharSequence s, int start, int before, int count) { applySearch(); }
            @Override public void afterTextChanged(Editable s) {}
        });
    }

    private void loadSection(Section target) {
        section = target;
        updateTabs();
        updateSectionHeader();
        loadingPanel.setVisibility(View.VISIBLE);
        emptyLabel.setVisibility(View.GONE);
        final int current = ++generation;

        io.execute(() -> {
            try {
                List<XuperProgram> result;
                if (target == Section.LIVE) result = repository.getLiveMexico();
                else if (target == Section.MOVIES) result = repository.getMovies();
                else if (target == Section.SERIES) result = repository.getSeries();
                else result = repository.getHome();
                List<XuperProgram> finalResult = result;
                runOnUiThread(() -> {
                    if (current != generation) return;
                    loaded.clear();
                    loaded.addAll(finalResult);
                    loadingPanel.setVisibility(View.GONE);
                    sectionStatus.setText(statusFor(target, finalResult.size()));
                    applySearch();
                });
            } catch (Exception e) {
                runOnUiThread(() -> {
                    if (current != generation) return;
                    loaded.clear();
                    adapter.submit(loaded);
                    loadingPanel.setVisibility(View.GONE);
                    emptyLabel.setVisibility(View.VISIBLE);
                    sectionStatus.setText("No se pudo cargar esta fuente pública");
                    Toast.makeText(this, e.getMessage() == null ? "Error al cargar catálogo" : e.getMessage(), Toast.LENGTH_LONG).show();
                });
            }
        });
    }

    private String statusFor(Section target, int size) {
        if (target == Section.LIVE) return size + " señales de México · API JSON pública";
        if (target == Section.MOVIES) return size + " películas/videos en español · Internet Archive";
        if (target == Section.SERIES) return size + " episodios/seriales abiertos · Internet Archive";
        return size + " recomendaciones · fuentes públicas";
    }

    private void applySearch() {
        String q = searchInput.getText().toString().trim().toLowerCase(Locale.ROOT);
        List<XuperProgram> visible = new ArrayList<>();
        for (XuperProgram p : loaded) {
            String haystack = (p.getName() + " " + p.getCategory() + " " + p.getCountry()).toLowerCase(Locale.ROOT);
            if (q.isEmpty() || haystack.contains(q)) visible.add(p);
        }
        adapter.submit(visible);
        emptyLabel.setVisibility(visible.isEmpty() ? View.VISIBLE : View.GONE);
        programList.setVisibility(visible.isEmpty() ? View.GONE : View.VISIBLE);
    }

    private void updateSectionHeader() {
        if (section == Section.HOME) sectionTitle.setText("Inicio");
        else if (section == Section.LIVE) sectionTitle.setText("TV México");
        else if (section == Section.MOVIES) sectionTitle.setText("Películas");
        else sectionTitle.setText("Series y episodios");
        sectionStatus.setText("Consultando APIs públicas…");
    }

    private void updateTabs() {
        int active = getColor(R.color.carlos_accent);
        int normal = getColor(R.color.white);
        ((TextView)findViewById(R.id.tab_home)).setTextColor(section == Section.HOME ? active : normal);
        ((TextView)findViewById(R.id.tab_live)).setTextColor(section == Section.LIVE ? active : normal);
        ((TextView)findViewById(R.id.tab_movies)).setTextColor(section == Section.MOVIES ? active : normal);
        ((TextView)findViewById(R.id.tab_series)).setTextColor(section == Section.SERIES ? active : normal);
    }

    @Override public void onProgramSelected(XuperProgram program) {
        XuperMedia media = program.chooseMedia();
        if (media != null) {
            play(program, media);
            return;
        }
        if (!program.getId().startsWith("ia:")) {
            Toast.makeText(this, "No hay una señal compatible para este contenido.", Toast.LENGTH_SHORT).show();
            return;
        }
        loadingPanel.setVisibility(View.VISIBLE);
        io.execute(() -> {
            try {
                XuperProgram resolvedProgram = repository.resolveArchiveProgram(program);
                XuperMedia resolved = resolvedProgram.chooseMedia();
                runOnUiThread(() -> {
                    loadingPanel.setVisibility(View.GONE);
                    if (resolved == null) Toast.makeText(this, "Internet Archive no ofrece un archivo de video compatible para este elemento.", Toast.LENGTH_LONG).show();
                    else play(resolvedProgram, resolved);
                });
            } catch (Exception e) {
                runOnUiThread(() -> {
                    loadingPanel.setVisibility(View.GONE);
                    Toast.makeText(this, "No se pudo resolver el archivo de reproducción.", Toast.LENGTH_LONG).show();
                });
            }
        });
    }

    private void play(XuperProgram program, XuperMedia media) {
        ensurePlayer();
        playerTitle.setText(program.getName());
        playerStatus.setText("Conectando · " + (media.getQuality().isEmpty() ? "automático" : media.getQuality()));
        playerPanel.setVisibility(View.VISIBLE);
        MediaItem.Builder item = new MediaItem.Builder().setUri(media.getUrl());
        String lower = media.getUrl().toLowerCase(Locale.ROOT);
        if (lower.contains(".m3u8")) item.setMimeType(MimeTypes.APPLICATION_M3U8);
        else if (lower.contains(".mpd")) item.setMimeType(MimeTypes.APPLICATION_MPD);
        player.setMediaItem(item.build());
        player.prepare();
        player.play();
    }

    private void ensurePlayer() {
        if (player != null) return;
        player = new ExoPlayer.Builder(this).build();
        playerView.setPlayer(player);
        player.addListener(new Player.Listener() {
            @Override public void onPlaybackStateChanged(int state) {
                if (state == Player.STATE_READY) {
                    playerStatus.setText(R.string.player_live);
                    playerStatus.setTextColor(getColor(R.color.carlos_accent));
                } else if (state == Player.STATE_BUFFERING) {
                    playerStatus.setText(R.string.player_connecting);
                    playerStatus.setTextColor(getColor(R.color.carlos_text_secondary));
                }
            }
            @Override public void onPlayerError(PlaybackException error) {
                playerStatus.setText(R.string.player_error);
                playerStatus.setTextColor(getColor(R.color.carlos_error));
            }
        });
    }

    private void closePlayer() {
        if (fullscreen) exitFullscreen();
        if (player != null) { player.stop(); player.clearMediaItems(); }
        playerPanel.setVisibility(View.GONE);
    }

    private void toggleFullscreen() {
        if (fullscreen) { exitFullscreen(); return; }
        fullscreen = true;
        playerToolbar.setVisibility(View.GONE);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN);
        getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_FULLSCREEN | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
        setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE);
    }

    private void exitFullscreen() {
        fullscreen = false;
        playerToolbar.setVisibility(View.VISIBLE);
        getWindow().clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN);
        getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_VISIBLE);
        setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED);
    }

    @Override public void onBackPressed() {
        if (fullscreen) exitFullscreen();
        else if (playerPanel.getVisibility() == View.VISIBLE) closePlayer();
        else super.onBackPressed();
    }

    @Override protected void onDestroy() {
        io.shutdownNow();
        if (adapter != null) adapter.release();
        if (player != null) player.release();
        super.onDestroy();
    }
}
