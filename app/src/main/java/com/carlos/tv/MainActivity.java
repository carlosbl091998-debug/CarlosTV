package com.carlos.tv;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.pm.ActivityInfo;
import android.graphics.Bitmap;
import android.net.Uri;
import android.os.Bundle;
import android.os.Message;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.webkit.CookieManager;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.ProgressBar;

import java.io.ByteArrayInputStream;
import java.util.Locale;

public class MainActivity extends Activity {

    private static final String START_URL = "https://rojadirectaa.net/";

    private static final String[] BLOCKED_AD_HOSTS = {
            "doubleclick.net",
            "googlesyndication.com",
            "googleadservices.com",
            "adservice.google.com",
            "popads.net",
            "popcash.net",
            "propellerads.com",
            "adsterra.com",
            "exoclick.com",
            "trafficjunky.net",
            "onclicka.com",
            "onclkds.com",
            "monetag.com",
            "highperformanceformat.com",
            "highperformancedisplayformat.com",
            "histats.com",
            "juicysads.com",
            "revcontent.com",
            "taboola.com",
            "outbrain.com"
    };

    private static final String PAGE_GUARD_JS =
            "(function(){"
                    + "if(window.__carlosTvGuardInstalled){return;}"
                    + "window.__carlosTvGuardInstalled=true;"
                    + "try{Object.defineProperty(window,'open',{value:function(){return null;},writable:false,configurable:false});}"
                    + "catch(e){window.open=function(){return null;};}"
                    + "var blocked=['doubleclick.net','googlesyndication.com','googleadservices.com','popads.net','popcash.net','propellerads.com','adsterra.com','exoclick.com','trafficjunky.net','onclkds.com','monetag.com','highperformanceformat.com','highperformancedisplayformat.com'];"
                    + "function isBlocked(value){value=(value||'').toLowerCase();return blocked.some(function(item){return value.indexOf(item)!==-1;});}"
                    + "function clean(root){"
                    + "var area=(root&&root.querySelectorAll)?root:document;"
                    + "area.querySelectorAll('a[target]').forEach(function(a){a.setAttribute('target','_self');});"
                    + "area.querySelectorAll('script[src],iframe[src],a[href]').forEach(function(el){"
                    + "var value=el.getAttribute('src')||el.getAttribute('href')||'';"
                    + "if(isBlocked(value)){if(el.tagName==='A'){el.removeAttribute('href');el.style.display='none';}else{el.remove();}}"
                    + "});}"
                    + "var style=document.createElement('style');"
                    + "style.textContent='.adsbygoogle,[id^=google_ads],[class*=popunder],[class*=interstitial-ad]{display:none!important;}';"
                    + "(document.head||document.documentElement).appendChild(style);"
                    + "clean(document);"
                    + "new MutationObserver(function(items){items.forEach(function(item){item.addedNodes.forEach(function(node){if(node.nodeType===1){clean(node);}});});})"
                    + ".observe(document.documentElement,{childList:true,subtree:true});"
                    + "})();";

    private FrameLayout fullscreenContainer;
    private WebView webView;
    private ProgressBar progress;
    private View chromeContainer;
    private View loadingPanel;
    private View errorPanel;
    private View backButton;
    private View customView;
    private WebChromeClient.CustomViewCallback customViewCallback;
    private int originalOrientation;
    private boolean firstPageLoaded;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        fullscreenContainer = findViewById(R.id.fullscreen_container);
        chromeContainer = findViewById(R.id.chrome_container);
        webView = findViewById(R.id.web_view);
        progress = findViewById(R.id.progress);
        loadingPanel = findViewById(R.id.loading_panel);
        errorPanel = findViewById(R.id.error_panel);
        backButton = findViewById(R.id.back_button);

        configureWebView();
        configureNativeControls();

        if (savedInstanceState == null || webView.restoreState(savedInstanceState) == null) {
            webView.loadUrl(START_URL);
        } else {
            firstPageLoaded = true;
            loadingPanel.setVisibility(View.GONE);
            updateBackButton();
        }
    }

    private void configureNativeControls() {
        backButton.setOnClickListener(v -> {
            if (webView.canGoBack()) {
                webView.goBack();
            } else {
                webView.loadUrl(START_URL);
            }
        });

        findViewById(R.id.home_button).setOnClickListener(v -> webView.loadUrl(START_URL));
        findViewById(R.id.refresh_button).setOnClickListener(v -> webView.reload());
        findViewById(R.id.retry_button).setOnClickListener(v -> {
            errorPanel.setVisibility(View.GONE);
            loadingPanel.setVisibility(View.VISIBLE);
            webView.loadUrl(START_URL);
        });
    }

    @SuppressLint("SetJavaScriptEnabled")
    private void configureWebView() {
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);
        settings.setLoadsImagesAutomatically(true);
        settings.setMediaPlaybackRequiresUserGesture(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE);
        settings.setSupportZoom(true);
        settings.setBuiltInZoomControls(true);
        settings.setDisplayZoomControls(false);
        settings.setSupportMultipleWindows(false);
        settings.setJavaScriptCanOpenWindowsAutomatically(false);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);

        webView.setVerticalScrollBarEnabled(false);
        webView.setOverScrollMode(View.OVER_SCROLL_NEVER);

        CookieManager cookieManager = CookieManager.getInstance();
        cookieManager.setAcceptCookie(true);
        cookieManager.setAcceptThirdPartyCookies(webView, true);

        webView.setWebViewClient(new CarlosWebViewClient());
        webView.setWebChromeClient(new CarlosWebChromeClient());
    }

    private boolean isBlockedAdHost(Uri uri) {
        String host = uri == null ? null : uri.getHost();
        if (host == null) {
            return false;
        }

        host = host.toLowerCase(Locale.US);
        for (String blockedHost : BLOCKED_AD_HOSTS) {
            if (host.equals(blockedHost) || host.endsWith("." + blockedHost)) {
                return true;
            }
        }
        return false;
    }

    private WebResourceResponse emptyResponse() {
        return new WebResourceResponse(
                "text/plain",
                "UTF-8",
                new ByteArrayInputStream(new byte[0]));
    }

    private void installPageGuard(WebView view) {
        view.evaluateJavascript(PAGE_GUARD_JS, null);
    }

    private void updateBackButton() {
        boolean enabled = webView.canGoBack();
        backButton.setEnabled(enabled);
        backButton.setAlpha(enabled ? 1.0f : 0.45f);
    }

    private final class CarlosWebViewClient extends WebViewClient {
        @Override
        public void onPageStarted(WebView view, String url, Bitmap favicon) {
            progress.setVisibility(View.VISIBLE);
            errorPanel.setVisibility(View.GONE);
            if (!firstPageLoaded) {
                loadingPanel.setVisibility(View.VISIBLE);
            }
        }

        @Override
        public void onPageCommitVisible(WebView view, String url) {
            installPageGuard(view);
        }

        @Override
        public void onPageFinished(WebView view, String url) {
            progress.setVisibility(View.GONE);
            loadingPanel.setVisibility(View.GONE);
            firstPageLoaded = true;
            installPageGuard(view);
            updateBackButton();
            CookieManager.getInstance().flush();
        }

        @Override
        public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
            Uri uri = request.getUrl();
            String scheme = uri.getScheme();
            if (!("http".equalsIgnoreCase(scheme) || "https".equalsIgnoreCase(scheme))) {
                return true;
            }
            return isBlockedAdHost(uri);
        }

        @Override
        public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
            if (isBlockedAdHost(request.getUrl())) {
                return emptyResponse();
            }
            return super.shouldInterceptRequest(view, request);
        }

        @Override
        public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
            if (request.isForMainFrame()) {
                progress.setVisibility(View.GONE);
                loadingPanel.setVisibility(View.GONE);
                errorPanel.setVisibility(View.VISIBLE);
            }
        }
    }

    private final class CarlosWebChromeClient extends WebChromeClient {
        @Override
        public void onProgressChanged(WebView view, int newProgress) {
            progress.setProgress(newProgress);
            progress.setVisibility(newProgress >= 100 ? View.GONE : View.VISIBLE);
        }

        @Override
        public void onShowCustomView(View view, CustomViewCallback callback) {
            if (customView != null) {
                callback.onCustomViewHidden();
                return;
            }

            customView = view;
            customViewCallback = callback;
            originalOrientation = getRequestedOrientation();

            chromeContainer.setVisibility(View.GONE);
            fullscreenContainer.setVisibility(View.VISIBLE);
            fullscreenContainer.addView(customView, new FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT));
            getWindow().addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN);
            getWindow().getDecorView().setSystemUiVisibility(
                    View.SYSTEM_UI_FLAG_FULLSCREEN
                            | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                            | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
            setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_SENSOR);
        }

        @Override
        public void onHideCustomView() {
            hideCustomView();
        }

        @Override
        public boolean onCreateWindow(WebView view, boolean isDialog, boolean isUserGesture, Message resultMsg) {
            return false;
        }
    }

    private void hideCustomView() {
        if (customView == null) {
            return;
        }

        fullscreenContainer.removeView(customView);
        fullscreenContainer.setVisibility(View.GONE);
        customView = null;
        chromeContainer.setVisibility(View.VISIBLE);
        getWindow().clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN);
        getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_VISIBLE);
        setRequestedOrientation(originalOrientation);

        if (customViewCallback != null) {
            customViewCallback.onCustomViewHidden();
            customViewCallback = null;
        }
    }

    @Override
    public void onBackPressed() {
        if (customView != null) {
            hideCustomView();
        } else if (webView.canGoBack()) {
            webView.goBack();
        } else {
            super.onBackPressed();
        }
    }

    @Override
    protected void onSaveInstanceState(Bundle outState) {
        webView.saveState(outState);
        super.onSaveInstanceState(outState);
    }

    @Override
    protected void onPause() {
        webView.onPause();
        super.onPause();
    }

    @Override
    protected void onResume() {
        super.onResume();
        webView.onResume();
    }

    @Override
    protected void onDestroy() {
        if (webView != null) {
            webView.stopLoading();
            webView.setWebChromeClient(null);
            webView.setWebViewClient(null);
            webView.destroy();
        }
        super.onDestroy();
    }
}
