package com.carlos.tv;

import android.app.Activity;
import android.content.SharedPreferences;
import android.content.pm.ActivityInfo;
import android.os.Bundle;
import android.text.Editable;
import android.text.InputType;
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
    private final XtreamClient portalClient = new XtreamClient();
    private LocalCatalogRepository localCatalog;

    private SharedPreferences prefs;
    private ProgramAdapter adapter;
    private EditText serverInput, userInput, passInput, searchInput;
    private RecyclerView programList;
    private TextView emptyLabel, sectionTitle, sectionStatus, portalBadge;
    private View loginPanel, catalogPanel, loadingPanel, playerPanel, playerToolbar;
    private PlayerView playerView;
    private TextView playerTitle, playerStatus;
    private ExoPlayer player;
    private Section section = Section.HOME;
    private boolean fullscreen;
    private boolean usePortal;
    private int generation;

    @Override protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        prefs = getSharedPreferences("carlos_portal", MODE_PRIVATE);
        localCatalog = new LocalCatalogRepository(this);
        bindViews();
        configureUi();
        restorePortalFields();
        showLocalCatalog();
    }

    private void bindViews() {
        loginPanel = findViewById(R.id.login_panel);
        catalogPanel = findViewById(R.id.catalog_panel);
        serverInput = findViewById(R.id.server_input);
        userInput = findViewById(R.id.user_input);
        passInput = findViewById(R.id.pass_input);
        searchInput = findViewById(R.id.search_input);
        programList = findViewById(R.id.program_list);
        emptyLabel = findViewById(R.id.empty_label);
        sectionTitle = findViewById(R.id.section_title);
        sectionStatus = findViewById(R.id.section_status);
        portalBadge = findViewById(R.id.portal_badge);
        loadingPanel = findViewById(R.id.loading_panel);
        playerPanel = findViewById(R.id.player_panel);
        playerToolbar = findViewById(R.id.player_toolbar);
        playerView = findViewById(R.id.player_view);
        playerTitle = findViewById(R.id.player_title);
        playerStatus = findViewById(R.id.player_status);
    }

    private void configureUi() {
        passInput.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
        adapter = new ProgramAdapter(this);
        int columns = getResources().getConfiguration().screenWidthDp >= 700 ? 5 : 2;
        programList.setLayoutManager(new GridLayoutManager(this, columns));
        programList.setAdapter(adapter);
        programList.setHasFixedSize(true);

        findViewById(R.id.connect_button).setOnClickListener(v -> connectPortal());
        findViewById(R.id.change_portal_button).setOnClickListener(v -> showPortalSettings());
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

    private void restorePortalFields() {
        serverInput.setText(prefs.getString("server", ""));
        userInput.setText(prefs.getString("username", ""));
        passInput.setText(prefs.getString("password", ""));
    }

    private void showLocalCatalog() {
        generation++;
        usePortal = false;
        loginPanel.setVisibility(View.GONE);
        catalogPanel.setVisibility(View.VISIBLE);
        loadingPanel.setVisibility(View.GONE);
        portalBadge.setText("CARLOS TV");
        section = Section.HOME;
        loadSection(Section.HOME);
    }

    private void showPortalSettings() {
        generation++;
        loginPanel.setVisibility(View.VISIBLE);
        catalogPanel.setVisibility(View.GONE);
        loadingPanel.setVisibility(View.GONE);
    }

    private void connectPortal() {
        String server = serverInput.getText().toString().trim();
        String user = userInput.getText().toString().trim();
        String pass = passInput.getText().toString();
        if (server.isEmpty() || user.isEmpty() || pass.isEmpty()) {
            Toast.makeText(this, "Escribe servidor, usuario y contraseña.", Toast.LENGTH_SHORT).show();
            return;
        }
        portalClient.configure(server, user, pass);
        loadingPanel.setVisibility(View.VISIBLE);
        final int current = ++generation;
        io.execute(() -> {
            try {
                XtreamClient.AuthResult auth = portalClient.authenticate();
                runOnUiThread(() -> {
                    if (current != generation) return;
                    loadingPanel.setVisibility(View.GONE);
                    if (!auth.ok) {
                        Toast.makeText(this, auth.status, Toast.LENGTH_LONG).show();
                        return;
                    }
                    prefs.edit().putString("server", server).putString("username", user).putString("password", pass).apply();
                    usePortal = true;
                    loginPanel.setVisibility(View.GONE);
                    catalogPanel.setVisibility(View.VISIBLE);
                    portalBadge.setText("PORTAL");
                    loadSection(Section.HOME);
                });
            } catch (Exception e) {
                runOnUiThread(() -> {
                    if (current != generation) return;
                    loadingPanel.setVisibility(View.GONE);
                    Toast.makeText(this, "Portal no disponible: " + safe(e.getMessage()) + ". Carlos TV local sigue disponible.", Toast.LENGTH_LONG).show();
                });
            }
        });
    }

    private void loadSection(Section target) {
        section = target;
        updateTabs();
        updateHeader("Cargando contenido…");
        loadingPanel.setVisibility(View.VISIBLE);
        emptyLabel.setVisibility(View.GONE);
        final int current = ++generation;
        io.execute(() -> {
            try {
                List<XuperProgram> result;
                if (usePortal) result = loadPortalSection(target);
                else result = loadLocalSection(target);
                List<XuperProgram> finalResult = result;
                runOnUiThread(() -> {
                    if (current != generation) return;
                    loaded.clear();
                    loaded.addAll(finalResult);
                    loadingPanel.setVisibility(View.GONE);
                    updateHeader(statusFor(target, finalResult.size()));
                    applySearch();
                });
            } catch (Exception e) {
                runOnUiThread(() -> {
                    if (current != generation) return;
                    loadingPanel.setVisibility(View.GONE);
                    loaded.clear();
                    adapter.submit(loaded);
                    emptyLabel.setVisibility(View.VISIBLE);
                    sectionStatus.setText("No se pudo cargar esta sección");
                    Toast.makeText(this, safe(e.getMessage()), Toast.LENGTH_LONG).show();
                });
            }
        });
    }

    private List<XuperProgram> loadLocalSection(Section target) throws Exception {
        if (target == Section.LIVE) return localCatalog.getLive();
        if (target == Section.MOVIES) return localCatalog.getMovies();
        if (target == Section.SERIES) return localCatalog.getSeries();
        return localCatalog.getHome();
    }

    private List<XuperProgram> loadPortalSection(Section target) throws Exception {
        if (target == Section.LIVE) return portalClient.getLive();
        if (target == Section.MOVIES) return portalClient.getMovies();
        if (target == Section.SERIES) return portalClient.getSeries();
        List<XuperProgram> result = new ArrayList<>();
        List<XuperProgram> live = portalClient.getLive();
        List<XuperProgram> movies = portalClient.getMovies();
        List<XuperProgram> series = portalClient.getSeries();
        result.addAll(live.subList(0, Math.min(12, live.size())));
        result.addAll(movies.subList(0, Math.min(12, movies.size())));
        result.addAll(series.subList(0, Math.min(8, series.size())));
        return result;
    }

    private String statusFor(Section target, int size) {
        String source = usePortal ? "portal" : "biblioteca Carlos TV";
        if (target == Section.LIVE) return size + " canales · " + source;
        if (target == Section.MOVIES) return size + " películas / VOD · " + source;
        if (target == Section.SERIES) return size + " episodios y series · " + source;
        return size + " contenidos destacados · " + source;
    }

    private void updateHeader(String status) {
        if (section == Section.HOME) sectionTitle.setText("Para ti");
        else if (section == Section.LIVE) sectionTitle.setText("TV en vivo");
        else if (section == Section.MOVIES) sectionTitle.setText("Películas");
        else sectionTitle.setText("Series");
        sectionStatus.setText(status);
    }

    private void updateTabs() {
        int active = getColor(R.color.carlos_accent);
        int normal = getColor(R.color.carlos_text_secondary);
        ((TextView)findViewById(R.id.tab_home)).setTextColor(section == Section.HOME ? active : normal);
        ((TextView)findViewById(R.id.tab_live)).setTextColor(section == Section.LIVE ? active : normal);
        ((TextView)findViewById(R.id.tab_movies)).setTextColor(section == Section.MOVIES ? active : normal);
        ((TextView)findViewById(R.id.tab_series)).setTextColor(section == Section.SERIES ? active : normal);
    }

    private void applySearch() {
        String q = searchInput.getText().toString().trim().toLowerCase(Locale.ROOT);
        List<XuperProgram> visible = new ArrayList<>();
        for (XuperProgram p : loaded) {
            String h = (p.getName() + " " + p.getCategory() + " " + p.getCountry()).toLowerCase(Locale.ROOT);
            if (q.isEmpty() || h.contains(q)) visible.add(p);
        }
        adapter.submit(visible);
        emptyLabel.setVisibility(visible.isEmpty() ? View.VISIBLE : View.GONE);
        programList.setVisibility(visible.isEmpty() ? View.GONE : View.VISIBLE);
    }

    @Override public void onProgramSelected(XuperProgram program) {
        XuperMedia media = program.chooseMedia();
        if (media != null) { play(program, media); return; }
        if (usePortal && program.getId().startsWith("series:")) {
            loadingPanel.setVisibility(View.VISIBLE);
            io.execute(() -> {
                try {
                    XuperProgram resolved = portalClient.resolveSeriesFirstEpisode(program);
                    XuperMedia m = resolved.chooseMedia();
                    runOnUiThread(() -> {
                        loadingPanel.setVisibility(View.GONE);
                        if (m == null) Toast.makeText(this, "La serie no devolvió episodios reproducibles.", Toast.LENGTH_LONG).show();
                        else play(resolved, m);
                    });
                } catch (Exception e) {
                    runOnUiThread(() -> {
                        loadingPanel.setVisibility(View.GONE);
                        Toast.makeText(this, "No se pudo abrir la serie.", Toast.LENGTH_LONG).show();
                    });
                }
            });
            return;
        }
        Toast.makeText(this, "No hay una señal reproducible.", Toast.LENGTH_SHORT).show();
    }

    private void play(XuperProgram program, XuperMedia media) {
        ensurePlayer();
        playerTitle.setText(program.getName());
        playerStatus.setText("Conectando…");
        playerStatus.setTextColor(getColor(R.color.carlos_text_secondary));
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
                    playerStatus.setText("REPRODUCIENDO · Carlos TV");
                    playerStatus.setTextColor(getColor(R.color.carlos_accent));
                } else if (state == Player.STATE_BUFFERING) {
                    playerStatus.setText("Cargando stream…");
                    playerStatus.setTextColor(getColor(R.color.carlos_text_secondary));
                }
            }
            @Override public void onPlayerError(PlaybackException error) {
                playerStatus.setText("Esta fuente no respondió. Prueba otro contenido.");
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

    private static String safe(String s) { return s == null || s.trim().isEmpty() ? "Error de conexión" : s; }

    @Override public void onBackPressed() {
        if (fullscreen) exitFullscreen();
        else if (playerPanel.getVisibility() == View.VISIBLE) closePlayer();
        else if (loginPanel.getVisibility() == View.VISIBLE) showLocalCatalog();
        else super.onBackPressed();
    }

    @Override protected void onDestroy() {
        io.shutdownNow();
        if (adapter != null) adapter.release();
        if (player != null) player.release();
        super.onDestroy();
    }
}
