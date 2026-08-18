package com.carlos.tv;

import android.app.Activity;
import android.content.SharedPreferences;
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

import java.io.InputStream;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

@UnstableApi
public class MainActivity extends Activity implements ChannelAdapter.Listener {
    private enum Section { HOME, LIVE, FAVORITES }

    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private final List<Channel> allChannels = new ArrayList<>();

    private SharedPreferences favorites;
    private ChannelAdapter adapter;
    private EditText searchInput;
    private RecyclerView channelList;
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

    @Override protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        favorites = getSharedPreferences("carlos_favorites", MODE_PRIVATE);
        bindViews();
        configureUi();
        loadMexicoCatalog();
    }

    private void bindViews() {
        channelList = findViewById(R.id.program_list);
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
        adapter = new ChannelAdapter(this, this);
        int columns = getResources().getConfiguration().screenWidthDp >= 700 ? 4 : 2;
        channelList.setLayoutManager(new GridLayoutManager(this, columns));
        channelList.setAdapter(adapter);
        channelList.setHasFixedSize(true);

        findViewById(R.id.tab_home).setOnClickListener(v -> selectSection(Section.HOME));
        findViewById(R.id.tab_live).setOnClickListener(v -> selectSection(Section.LIVE));
        findViewById(R.id.tab_favorites).setOnClickListener(v -> selectSection(Section.FAVORITES));
        findViewById(R.id.close_player_button).setOnClickListener(v -> closePlayer());
        findViewById(R.id.fullscreen_button).setOnClickListener(v -> toggleFullscreen());

        searchInput.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
            @Override public void onTextChanged(CharSequence s, int start, int before, int count) { refreshList(); }
            @Override public void afterTextChanged(Editable s) {}
        });
    }

    private void loadMexicoCatalog() {
        loadingPanel.setVisibility(View.VISIBLE);
        io.execute(() -> {
            try (InputStream in = getAssets().open("mexico_tv.m3u")) {
                M3uParser.ParseResult result = new M3uParser().parse(in);
                List<Channel> channels = result.getChannels();
                for (Channel c : channels) {
                    c.setFavorite(favorites.getBoolean(c.getStreamUrl(), false));
                }
                runOnUiThread(() -> {
                    allChannels.clear();
                    allChannels.addAll(channels);
                    loadingPanel.setVisibility(View.GONE);
                    refreshList();
                });
            } catch (Exception e) {
                runOnUiThread(() -> {
                    loadingPanel.setVisibility(View.GONE);
                    emptyLabel.setVisibility(View.VISIBLE);
                    sectionStatus.setText("No se pudo abrir el catálogo local");
                    Toast.makeText(this, "Error al cargar la lista de México", Toast.LENGTH_LONG).show();
                });
            }
        });
    }

    private void selectSection(Section target) {
        section = target;
        updateTabs();
        refreshList();
    }

    private void refreshList() {
        String q = searchInput.getText().toString().trim().toLowerCase(Locale.ROOT);
        List<Channel> visible = new ArrayList<>();
        for (Channel c : allChannels) {
            if (section == Section.FAVORITES && !c.isFavorite()) continue;
            String haystack = (c.getName() + " " + c.getCategory() + " " + c.getCountry()).toLowerCase(Locale.ROOT);
            if (!q.isEmpty() && !haystack.contains(q)) continue;
            visible.add(c);
        }

        adapter.submit(visible);
        emptyLabel.setVisibility(visible.isEmpty() ? View.VISIBLE : View.GONE);
        channelList.setVisibility(visible.isEmpty() ? View.GONE : View.VISIBLE);

        if (section == Section.FAVORITES) {
            sectionTitle.setText("Mis favoritos");
            sectionStatus.setText(visible.size() + " canales guardados");
        } else if (section == Section.LIVE) {
            sectionTitle.setText("TV de México");
            sectionStatus.setText(visible.size() + " señales en vivo · catálogo M3U");
        } else {
            sectionTitle.setText("México en vivo");
            sectionStatus.setText(visible.size() + " canales seleccionados para Carlos TV");
        }
    }

    private void updateTabs() {
        int active = getColor(R.color.carlos_accent);
        int normal = getColor(R.color.carlos_text_secondary);
        ((TextView)findViewById(R.id.tab_home)).setTextColor(section == Section.HOME ? active : normal);
        ((TextView)findViewById(R.id.tab_live)).setTextColor(section == Section.LIVE ? active : normal);
        ((TextView)findViewById(R.id.tab_favorites)).setTextColor(section == Section.FAVORITES ? active : normal);
    }

    @Override public void onChannelSelected(Channel channel) {
        ensurePlayer();
        playerTitle.setText(channel.getName());
        playerStatus.setText("Conectando señal en vivo…");
        playerStatus.setTextColor(getColor(R.color.carlos_text_secondary));
        playerPanel.setVisibility(View.VISIBLE);

        MediaItem.Builder item = new MediaItem.Builder().setUri(channel.getStreamUrl());
        String lower = channel.getStreamUrl().toLowerCase(Locale.ROOT);
        if (lower.contains(".m3u8")) item.setMimeType(MimeTypes.APPLICATION_M3U8);
        else if (lower.contains(".mpd")) item.setMimeType(MimeTypes.APPLICATION_MPD);
        player.setMediaItem(item.build());
        player.prepare();
        player.play();
    }

    @Override public void onFavoriteChanged(Channel channel) {
        favorites.edit().putBoolean(channel.getStreamUrl(), channel.isFavorite()).apply();
        if (section == Section.FAVORITES) refreshList();
    }

    private void ensurePlayer() {
        if (player != null) return;
        player = new ExoPlayer.Builder(this).build();
        playerView.setPlayer(player);
        player.addListener(new Player.Listener() {
            @Override public void onPlaybackStateChanged(int state) {
                if (state == Player.STATE_READY) {
                    playerStatus.setText("EN VIVO · Carlos TV");
                    playerStatus.setTextColor(getColor(R.color.carlos_accent));
                } else if (state == Player.STATE_BUFFERING) {
                    playerStatus.setText("Cargando señal…");
                    playerStatus.setTextColor(getColor(R.color.carlos_text_secondary));
                }
            }
            @Override public void onPlayerError(PlaybackException error) {
                playerStatus.setText("Esta señal no respondió. Prueba otro canal.");
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
