package com.carlos.tv;

import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ActivityInfo;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Bundle;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;

import androidx.annotation.Nullable;
import androidx.media3.common.MediaItem;
import androidx.media3.common.MimeTypes;
import androidx.media3.common.PlaybackException;
import androidx.media3.common.Player;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.ui.PlayerView;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

@UnstableApi
public class MainActivity extends Activity implements ChannelAdapter.Listener {

    private static final int REQUEST_OPEN_PLAYLIST = 7301;
    private static final String PREFS = "carlos_tv_preferences";
    private static final String PREF_FAVORITES = "favorite_streams";
    private static final String PREF_CUSTOM_URI = "custom_playlist_uri";
    private static final String ALL_CATEGORIES = "Todos";

    private final List<Channel> allChannels = new ArrayList<>();
    private final Set<String> favoriteUrls = new HashSet<>();
    private final ExecutorService ioExecutor = Executors.newSingleThreadExecutor();

    private PlaylistRepository repository;
    private SharedPreferences preferences;
    private ChannelAdapter adapter;
    private RecyclerView recyclerView;
    private EditText searchInput;
    private LinearLayout categoryContainer;
    private TextView catalogSummary;
    private TextView sourceLabel;
    private TextView emptyLabel;
    private View loadingPanel;
    private View errorPanel;
    private View playerPanel;
    private View playerToolbar;
    private View playerInfo;
    private TextView playerTitle;
    private TextView playerMetadata;
    private TextView playerStatus;
    private ProgressBar playerProgress;
    private PlayerView playerView;
    private TextView navHome;
    private TextView navFavorites;
    private ExoPlayer player;
    private Uri customPlaylistUri;
    private String selectedCategory = ALL_CATEGORIES;
    private boolean favoritesOnly;
    private boolean fullscreen;
    private int loadGeneration;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        repository = new PlaylistRepository(this);
        preferences = getSharedPreferences(PREFS, MODE_PRIVATE);
        Set<String> storedFavorites = preferences.getStringSet(
                PREF_FAVORITES,
                Collections.emptySet());
        favoriteUrls.addAll(storedFavorites);

        bindViews();
        configureCatalog();
        configureActions();

        String storedUri = preferences.getString(PREF_CUSTOM_URI, "");
        if (storedUri != null && !storedUri.isEmpty()) {
            customPlaylistUri = Uri.parse(storedUri);
            loadCustomPlaylist(customPlaylistUri);
        } else {
            loadDefaultPlaylist(false);
        }
    }

    private void bindViews() {
        recyclerView = findViewById(R.id.channel_list);
        searchInput = findViewById(R.id.search_input);
        categoryContainer = findViewById(R.id.category_container);
        catalogSummary = findViewById(R.id.catalog_summary);
        sourceLabel = findViewById(R.id.source_label);
        emptyLabel = findViewById(R.id.empty_label);
        loadingPanel = findViewById(R.id.loading_panel);
        errorPanel = findViewById(R.id.error_panel);
        playerPanel = findViewById(R.id.player_panel);
        playerToolbar = findViewById(R.id.player_toolbar);
        playerInfo = findViewById(R.id.player_info);
        playerTitle = findViewById(R.id.player_title);
        playerMetadata = findViewById(R.id.player_metadata);
        playerStatus = findViewById(R.id.player_status);
        playerProgress = findViewById(R.id.player_progress);
        playerView = findViewById(R.id.player_view);
        navHome = findViewById(R.id.nav_home);
        navFavorites = findViewById(R.id.nav_favorites);
    }

    private void configureCatalog() {
        adapter = new ChannelAdapter(this, this);
        recyclerView.setLayoutManager(new LinearLayoutManager(this));
        recyclerView.setAdapter(adapter);
        recyclerView.setHasFixedSize(true);

        searchInput.addTextChangedListener(new TextWatcher() {
            @Override
            public void beforeTextChanged(CharSequence value, int start, int count, int after) {
            }

            @Override
            public void onTextChanged(CharSequence value, int start, int before, int count) {
                applyFilters();
            }

            @Override
            public void afterTextChanged(Editable value) {
            }
        });
    }

    private void configureActions() {
        findViewById(R.id.import_button).setOnClickListener(view -> openPlaylistPicker());
        findViewById(R.id.header_import_button).setOnClickListener(view -> openPlaylistPicker());
        findViewById(R.id.bottom_import_button).setOnClickListener(view -> openPlaylistPicker());
        findViewById(R.id.refresh_button).setOnClickListener(view -> refreshActiveSource());
        findViewById(R.id.retry_button).setOnClickListener(view -> refreshActiveSource());
        findViewById(R.id.default_source_button).setOnClickListener(view -> useDefaultSource());

        navHome.setOnClickListener(view -> {
            favoritesOnly = false;
            selectedCategory = ALL_CATEGORIES;
            rebuildCategories();
            applyFilters();
            updateNavigation();
        });
        navFavorites.setOnClickListener(view -> {
            favoritesOnly = true;
            applyFilters();
            updateNavigation();
        });

        findViewById(R.id.close_player_button).setOnClickListener(view -> closePlayer());
        findViewById(R.id.fullscreen_button).setOnClickListener(view -> toggleFullscreen());
    }

    private void openPlaylistPicker() {
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("*/*");
        intent.putExtra(Intent.EXTRA_MIME_TYPES, new String[]{
                "application/x-mpegURL",
                "application/vnd.apple.mpegurl",
                "audio/mpegurl",
                "audio/x-mpegurl",
                "text/plain"
        });
        startActivityForResult(intent, REQUEST_OPEN_PLAYLIST);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, @Nullable Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != REQUEST_OPEN_PLAYLIST
                || resultCode != RESULT_OK
                || data == null
                || data.getData() == null) {
            return;
        }

        Uri uri = data.getData();
        int flags = data.getFlags()
                & (Intent.FLAG_GRANT_READ_URI_PERMISSION
                | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
        try {
            getContentResolver().takePersistableUriPermission(
                    uri,
                    flags & Intent.FLAG_GRANT_READ_URI_PERMISSION);
        } catch (SecurityException ignored) {
            // Algunos proveedores permiten leer sin ofrecer permiso persistente.
        }

        customPlaylistUri = uri;
        preferences.edit().putString(PREF_CUSTOM_URI, uri.toString()).apply();
        loadCustomPlaylist(uri);
    }

    private void refreshActiveSource() {
        if (customPlaylistUri != null) {
            loadCustomPlaylist(customPlaylistUri);
        } else {
            loadDefaultPlaylist(true);
        }
    }

    private void useDefaultSource() {
        customPlaylistUri = null;
        preferences.edit().remove(PREF_CUSTOM_URI).apply();
        loadDefaultPlaylist(true);
    }

    private void loadDefaultPlaylist(boolean forceRefresh) {
        runLoad(() -> repository.loadDefault(forceRefresh));
    }

    private void loadCustomPlaylist(Uri uri) {
        runLoad(() -> repository.loadFromDocument(uri));
    }

    private void runLoad(PlaylistTask task) {
        final int generation = ++loadGeneration;
        showLoading(true);
        errorPanel.setVisibility(View.GONE);

        ioExecutor.execute(() -> {
            try {
                PlaylistRepository.LoadResult result = task.load();
                runOnUiThread(() -> {
                    if (generation == loadGeneration) {
                        showLoadedChannels(result);
                    }
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (generation != loadGeneration) {
                        return;
                    }
                    showLoading(false);
                    if (allChannels.isEmpty()) {
                        errorPanel.setVisibility(View.VISIBLE);
                    }
                    Toast.makeText(
                            this,
                            error.getMessage() == null
                                    ? getString(R.string.connection_error)
                                    : error.getMessage(),
                            Toast.LENGTH_LONG).show();
                });
            }
        });
    }

    private void showLoadedChannels(PlaylistRepository.LoadResult result) {
        allChannels.clear();
        allChannels.addAll(result.getChannels());
        for (Channel channel : allChannels) {
            channel.setFavorite(favoriteUrls.contains(channel.getStreamUrl()));
        }

        selectedCategory = ALL_CATEGORIES;
        favoritesOnly = false;
        sourceLabel.setText(result.getSourceName()
                + " · "
                + allChannels.size()
                + " canales");
        showLoading(false);
        errorPanel.setVisibility(View.GONE);
        rebuildCategories();
        applyFilters();
        updateNavigation();
    }

    private void showLoading(boolean show) {
        loadingPanel.setVisibility(show ? View.VISIBLE : View.GONE);
    }

    private void rebuildCategories() {
        categoryContainer.removeAllViews();
        addCategoryChip(ALL_CATEGORIES);

        Map<String, Integer> counts = new HashMap<>();
        for (Channel channel : allChannels) {
            String category = channel.getCategory();
            Integer currentCount = counts.get(category);
            counts.put(category, currentCount == null ? 1 : currentCount + 1);
        }

        List<Map.Entry<String, Integer>> entries = new ArrayList<>(counts.entrySet());
        Collections.sort(entries, (left, right) -> {
            int byCount = Integer.compare(right.getValue(), left.getValue());
            return byCount != 0 ? byCount : left.getKey().compareTo(right.getKey());
        });

        int limit = Math.min(24, entries.size());
        for (int index = 0; index < limit; index++) {
            String category = entries.get(index).getKey();
            if (!ALL_CATEGORIES.equals(category)) {
                addCategoryChip(category);
            }
        }
    }

    private void addCategoryChip(String category) {
        TextView chip = new TextView(this);
        chip.setText(category);
        chip.setTextSize(13);
        chip.setTextColor(getColor(
                category.equals(selectedCategory)
                        ? R.color.carlos_background
                        : R.color.white));
        chip.setGravity(android.view.Gravity.CENTER);
        chip.setPadding(dp(17), dp(9), dp(17), dp(9));

        GradientDrawable background = new GradientDrawable();
        background.setCornerRadius(dp(18));
        if (category.equals(selectedCategory)) {
            background.setColor(getColor(R.color.carlos_lime));
        } else {
            background.setColor(getColor(R.color.carlos_surface_high));
            background.setStroke(dp(1), getColor(R.color.carlos_border));
        }
        chip.setBackground(background);

        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                dp(38));
        params.setMarginEnd(dp(8));
        chip.setLayoutParams(params);
        chip.setOnClickListener(view -> {
            selectedCategory = category;
            favoritesOnly = false;
            rebuildCategories();
            applyFilters();
            updateNavigation();
        });
        categoryContainer.addView(chip);
    }

    private void applyFilters() {
        String query = searchInput.getText().toString().trim().toLowerCase(Locale.getDefault());
        List<Channel> visible = new ArrayList<>();

        for (Channel channel : allChannels) {
            if (favoritesOnly && !channel.isFavorite()) {
                continue;
            }
            if (!ALL_CATEGORIES.equals(selectedCategory)
                    && !selectedCategory.equals(channel.getCategory())) {
                continue;
            }
            if (!query.isEmpty()) {
                String haystack = (channel.getName()
                        + " "
                        + channel.getMetadata()).toLowerCase(Locale.getDefault());
                if (!haystack.contains(query)) {
                    continue;
                }
            }
            visible.add(channel);
        }

        adapter.submit(visible);
        catalogSummary.setText(visible.size()
                + (visible.size() == 1 ? " canal disponible" : " canales disponibles"));
        emptyLabel.setVisibility(visible.isEmpty() ? View.VISIBLE : View.GONE);
        recyclerView.setVisibility(visible.isEmpty() ? View.GONE : View.VISIBLE);
    }

    private void updateNavigation() {
        navHome.setTextColor(getColor(
                favoritesOnly ? R.color.carlos_text_secondary : R.color.carlos_lime));
        navFavorites.setTextColor(getColor(
                favoritesOnly ? R.color.carlos_lime : R.color.carlos_text_secondary));
    }

    @Override
    public void onChannelSelected(Channel channel) {
        playChannel(channel);
    }

    @Override
    public void onFavoriteChanged(Channel channel) {
        if (channel.isFavorite()) {
            favoriteUrls.add(channel.getStreamUrl());
        } else {
            favoriteUrls.remove(channel.getStreamUrl());
        }
        preferences.edit()
                .putStringSet(PREF_FAVORITES, new HashSet<>(favoriteUrls))
                .apply();
        if (favoritesOnly) {
            applyFilters();
        }
    }

    private void playChannel(Channel channel) {
        ensurePlayer();
        playerTitle.setText(channel.getName());
        playerMetadata.setText(channel.getMetadata());
        playerStatus.setText(R.string.player_connecting);
        playerStatus.setTextColor(getColor(R.color.carlos_text_secondary));
        playerProgress.setVisibility(View.VISIBLE);
        playerPanel.setVisibility(View.VISIBLE);
        playerView.setKeepScreenOn(true);

        String lower = channel.getStreamUrl().toLowerCase(Locale.US);
        MediaItem.Builder item = new MediaItem.Builder().setUri(channel.getStreamUrl());
        if (lower.contains(".m3u8")) {
            item.setMimeType(MimeTypes.APPLICATION_M3U8);
        } else if (lower.contains(".mpd")) {
            item.setMimeType(MimeTypes.APPLICATION_MPD);
        }

        player.setMediaItem(item.build());
        player.prepare();
        player.play();
    }

    private void ensurePlayer() {
        if (player != null) {
            return;
        }
        player = new ExoPlayer.Builder(this).build();
        playerView.setPlayer(player);
        playerView.setControllerAutoShow(true);
        player.addListener(new Player.Listener() {
            @Override
            public void onPlaybackStateChanged(int playbackState) {
                if (playbackState == Player.STATE_BUFFERING) {
                    playerProgress.setVisibility(View.VISIBLE);
                    playerStatus.setText(R.string.player_connecting);
                } else if (playbackState == Player.STATE_READY) {
                    playerProgress.setVisibility(View.GONE);
                    playerStatus.setText(R.string.player_live);
                    playerStatus.setTextColor(getColor(R.color.carlos_lime));
                } else if (playbackState == Player.STATE_ENDED) {
                    playerProgress.setVisibility(View.GONE);
                }
            }

            @Override
            public void onPlayerError(PlaybackException error) {
                playerProgress.setVisibility(View.GONE);
                playerStatus.setText(R.string.player_error);
                playerStatus.setTextColor(getColor(R.color.carlos_error));
            }
        });
    }

    private void closePlayer() {
        if (fullscreen) {
            exitFullscreen();
        }
        if (player != null) {
            player.stop();
            player.clearMediaItems();
        }
        playerView.setKeepScreenOn(false);
        playerPanel.setVisibility(View.GONE);
    }

    private void toggleFullscreen() {
        if (fullscreen) {
            exitFullscreen();
            return;
        }
        fullscreen = true;
        playerToolbar.setVisibility(View.GONE);
        playerInfo.setVisibility(View.GONE);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN);
        getWindow().getDecorView().setSystemUiVisibility(
                View.SYSTEM_UI_FLAG_FULLSCREEN
                        | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                        | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
        setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE);
    }

    private void exitFullscreen() {
        fullscreen = false;
        playerToolbar.setVisibility(View.VISIBLE);
        playerInfo.setVisibility(View.VISIBLE);
        getWindow().clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN);
        getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_VISIBLE);
        setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED);
    }

    @Override
    public void onBackPressed() {
        if (fullscreen) {
            exitFullscreen();
        } else if (playerPanel.getVisibility() == View.VISIBLE) {
            closePlayer();
        } else {
            super.onBackPressed();
        }
    }

    @Override
    protected void onStop() {
        if (player != null) {
            player.pause();
        }
        super.onStop();
    }

    @Override
    protected void onDestroy() {
        ioExecutor.shutdownNow();
        if (adapter != null) {
            adapter.release();
        }
        if (player != null) {
            player.release();
            player = null;
        }
        super.onDestroy();
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private interface PlaylistTask {
        PlaylistRepository.LoadResult load() throws Exception;
    }
}
