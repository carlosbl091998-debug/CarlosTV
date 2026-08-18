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
    private final XtreamClient client = new XtreamClient();

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
    private int generation;

    @Override protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        prefs = getSharedPreferences("carlos_portal", MODE_PRIVATE);
        bindViews();
        configureUi();
        restoreCredentials();
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

        findViewById(R.id.connect_button).setOnClickListener(v -> connect());
        findViewById(R.id.change_portal_button).setOnClickListener(v -> showLogin());
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

    private void restoreCredentials() {
        serverInput.setText(prefs.getString("server", ""));
        userInput.setText(prefs.getString("username", ""));
        passInput.setText(prefs.getString("password", ""));
        if (!serverInput.getText().toString().isEmpty() && !userInput.getText().toString().isEmpty()) connect();
        else showLogin();
    }

    private void showLogin() {
        generation++;
        loginPanel.setVisibility(View.VISIBLE);
        catalogPanel.setVisibility(View.GONE);
        loadingPanel.setVisibility(View.GONE);
        portalBadge.setText("PORTAL");
    }

    private void connect() {
        String server = serverInput.getText().toString().trim();
        String user = userInput.getText().toString().trim();
        String pass = passInput.getText().toString();
        if (server.isEmpty() || user.isEmpty() || pass.isEmpty()) {
            Toast.makeText(this, "Escribe servidor, usuario y contraseña.", Toast.LENGTH_SHORT).show();
            return;
        }
        client.configure(server, user, pass);
        loadingPanel.setVisibility(View.VISIBLE);
        final int current = ++generation;
        io.execute(() -> {
            try {
                XtreamClient.AuthResult auth = client.authenticate();
                runOnUiThread(() -> {
                    if (current != generation) return;
                    loadingPanel.setVisibility(View.GONE);
                    if (!auth.ok) {
                        Toast.makeText(this, auth.status, Toast.LENGTH_LONG).show();
                        showLogin();
                        return;
                    }
                    prefs.edit().putString("server", server).putString("username", user).putString("password", pass).apply();
                    loginPanel.setVisibility(View.GONE);
                    catalogPanel.setVisibility(View.VISIBLE);
                    portalBadge.setText("CONECTADO");
                    loadSection(Section.HOME);
                });
            } catch (Exception e) {
                runOnUiThread(() -> {
                    if (current != generation) return;
                    loadingPanel.setVisibility(View.GONE);
                    Toast.makeText(this, "No se pudo conectar al portal: " + safe(e.getMessage()), Toast.LENGTH_LONG).show();
                    showLogin();
                });
            }
        });
    }

    private void loadSection(Section target) {
        if (!client.isConfigured()) { showLogin(); return; }
        section = target;
        updateTabs();
        updateHeader("Cargando catálogo del portal…");
        loadingPanel.setVisibility(View.VISIBLE);
        emptyLabel.setVisibility(View.GONE);
        final int current = ++generation;
        io.execute(() -> {
            try {
                List<XuperProgram> result;
                if (target == Section.LIVE) result = client.getLive();
                else if (target == Section.MOVIES) result = client.getMovies();
                else if (target == Section.SERIES) result = client.getSeries();
                else {
                    result = new ArrayList<>();
                    List<XuperProgram> live = client.getLive();
                    List<XuperProgram> movies = client.getMovies();
                    result.addAll(live.subList(0, Math.min(30, live.size())));
                    result.addAll(movies.subList(0, Math.min(30, movies.size())));
                }
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
                    sectionStatus.setText("Error al consultar el portal");
                    Toast.makeText(this, safe(e.getMessage()), Toast.LENGTH_LONG).show();
                });
            }
        });
    }

    private String statusFor(Section target, int size) {
        if (target == Section.LIVE) return size + " canales del portal";
        if (target == Section.MOVIES) return size + " películas / VOD";
        if (target == Section.SERIES) return size + " series";
        return size + " contenidos destacados";
    }

    private void updateHeader(String status) {
        if (section == Section.HOME) sectionTitle.setText("Inicio");
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
            String h = (p.getName() + " " + p.getCategory()).toLowerCase(Locale.ROOT);
            if (q.isEmpty() || h.contains(q)) visible.add(p);
        }
        adapter.submit(visible);
        emptyLabel.setVisibility(visible.isEmpty() ? View.VISIBLE : View.GONE);
        programList.setVisibility(visible.isEmpty() ? View.GONE : View.VISIBLE);
    }

    @Override public void onProgramSelected(XuperProgram program) {
        XuperMedia media = program.chooseMedia();
        if (media != null) { play(program, media); return; }
        if (!program.getId().startsWith("series:")) {
            Toast.makeText(this, "No hay una señal reproducible.", Toast.LENGTH_SHORT).show();
            return;
        }
        loadingPanel.setVisibility(View.VISIBLE);
        io.execute(() -> {
            try {
                XuperProgram resolved = client.resolveSeriesFirstEpisode(program);
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
    }

    private void play(XuperProgram program, XuperMedia media) {
        ensurePlayer();
        playerTitle.setText(program.getName());
        playerStatus.setText("Conectando al stream…");
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
                playerStatus.setText("El stream no respondió o requiere otro formato.");
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
        else if (catalogPanel.getVisibility() == View.VISIBLE) showLogin();
        else super.onBackPressed();
    }

    @Override protected void onDestroy() {
        io.shutdownNow();
        if (adapter != null) adapter.release();
        if (player != null) player.release();
        super.onDestroy();
    }
}
