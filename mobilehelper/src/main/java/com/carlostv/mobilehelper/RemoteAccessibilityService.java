package com.carlostv.mobilehelper;

import android.accessibilityservice.AccessibilityService;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.graphics.Rect;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;
import android.widget.Button;
import android.widget.GridLayout;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.List;

public class RemoteAccessibilityService extends AccessibilityService {
    private static final String XUPER_PACKAGE = "com.android.mgstv";

    private WindowManager windowManager;
    private LinearLayout overlay;
    private boolean overlayAttached = false;

    @Override
    protected void onServiceConnected() {
        super.onServiceConnected();
        windowManager = (WindowManager) getSystemService(WINDOW_SERVICE);
        buildOverlay();
        AccessibilityNodeInfo root = getRootInActiveWindow();
        if (root != null && root.getPackageName() != null && XUPER_PACKAGE.contentEquals(root.getPackageName())) {
            showOverlay();
        }
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        if (event == null || event.getPackageName() == null) return;
        String pkg = event.getPackageName().toString();
        if (XUPER_PACKAGE.equals(pkg)) {
            showOverlay();
        } else if (!getPackageName().equals(pkg) && event.getEventType() == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            hideOverlay();
        }
    }

    @Override
    public void onInterrupt() {
        hideOverlay();
    }

    @Override
    public void onDestroy() {
        hideOverlay();
        super.onDestroy();
    }

    private void buildOverlay() {
        overlay = new LinearLayout(this);
        overlay.setOrientation(LinearLayout.VERTICAL);
        overlay.setPadding(dp(6), dp(6), dp(6), dp(6));
        overlay.setBackgroundColor(Color.argb(205, 20, 20, 20));
        overlay.setContentDescription("Control táctil Xuper");

        LinearLayout top = new LinearLayout(this);
        top.setOrientation(LinearLayout.HORIZONTAL);
        top.setGravity(Gravity.CENTER_VERTICAL);

        TextView label = new TextView(this);
        label.setText("Xuper");
        label.setTextColor(Color.WHITE);
        label.setTextSize(12);
        LinearLayout.LayoutParams labelLp = new LinearLayout.LayoutParams(0, dp(34), 1f);
        top.addView(label, labelLp);

        Button back = smallButton("Atrás", "Volver");
        back.setOnClickListener(v -> performGlobalAction(GLOBAL_ACTION_BACK));
        top.addView(back, new LinearLayout.LayoutParams(dp(72), dp(34)));
        overlay.addView(top, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(36)));

        GridLayout pad = new GridLayout(this);
        pad.setColumnCount(3);
        pad.setRowCount(3);
        pad.setUseDefaultMargins(false);

        addPadSpacer(pad, 0, 0);
        addPadButton(pad, "↑", "Mover arriba", 0, 1, () -> move(Direction.UP));
        addPadSpacer(pad, 0, 2);
        addPadButton(pad, "←", "Mover izquierda", 1, 0, () -> move(Direction.LEFT));
        addPadButton(pad, "OK", "Aceptar", 1, 1, this::clickFocused);
        addPadButton(pad, "→", "Mover derecha", 1, 2, () -> move(Direction.RIGHT));
        addPadSpacer(pad, 2, 0);
        addPadButton(pad, "↓", "Mover abajo", 2, 1, () -> move(Direction.DOWN));
        addPadSpacer(pad, 2, 2);
        overlay.addView(pad, new LinearLayout.LayoutParams(dp(174), dp(156)));
    }

    private void addPadButton(GridLayout grid, String text, String description, int row, int col, Runnable action) {
        Button b = smallButton(text, description);
        b.setTextSize("OK".equals(text) ? 13 : 24);
        b.setOnClickListener(v -> action.run());
        GridLayout.LayoutParams lp = new GridLayout.LayoutParams(GridLayout.spec(row), GridLayout.spec(col));
        lp.width = dp(58);
        lp.height = dp(52);
        grid.addView(b, lp);
    }

    private void addPadSpacer(GridLayout grid, int row, int col) {
        View v = new View(this);
        GridLayout.LayoutParams lp = new GridLayout.LayoutParams(GridLayout.spec(row), GridLayout.spec(col));
        lp.width = dp(58);
        lp.height = dp(52);
        grid.addView(v, lp);
    }

    private Button smallButton(String text, String description) {
        Button b = new Button(this);
        b.setText(text);
        b.setAllCaps(false);
        b.setTextSize(12);
        b.setPadding(0, 0, 0, 0);
        b.setContentDescription(description);
        b.setMinWidth(0);
        b.setMinHeight(0);
        return b;
    }

    private WindowManager.LayoutParams overlayParams() {
        WindowManager.LayoutParams p = new WindowManager.LayoutParams(
                dp(186),
                dp(204),
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                        | WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
                        | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT);
        p.gravity = Gravity.END | Gravity.BOTTOM;
        p.x = dp(8);
        p.y = dp(20);
        p.alpha = 0.92f;
        return p;
    }

    private void showOverlay() {
        if (windowManager == null || overlay == null || overlayAttached) return;
        try {
            windowManager.addView(overlay, overlayParams());
            overlayAttached = true;
        } catch (Exception ignored) {}
    }

    private void hideOverlay() {
        if (!overlayAttached || windowManager == null || overlay == null) return;
        try { windowManager.removeView(overlay); } catch (Exception ignored) {}
        overlayAttached = false;
    }

    private enum Direction { UP, DOWN, LEFT, RIGHT }

    private void move(Direction direction) {
        AccessibilityNodeInfo root = getRootInActiveWindow();
        if (!isXuperRoot(root)) return;

        List<AccessibilityNodeInfo> nodes = new ArrayList<>();
        collectCandidates(root, nodes, 0);
        if (nodes.isEmpty()) return;

        AccessibilityNodeInfo current = root.findFocus(AccessibilityNodeInfo.FOCUS_ACCESSIBILITY);
        if (current == null) current = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT);
        if (current == null) {
            focusNode(nearestToScreenCenter(nodes));
            return;
        }

        Rect cr = new Rect();
        current.getBoundsInScreen(cr);
        if (cr.isEmpty()) {
            focusNode(nearestToScreenCenter(nodes));
            return;
        }

        float cx = cr.exactCenterX();
        float cy = cr.exactCenterY();
        AccessibilityNodeInfo best = null;
        double bestScore = Double.MAX_VALUE;

        for (AccessibilityNodeInfo n : nodes) {
            if (n == current) continue;
            Rect r = new Rect();
            n.getBoundsInScreen(r);
            if (r.isEmpty()) continue;
            float dx = r.exactCenterX() - cx;
            float dy = r.exactCenterY() - cy;
            float primary;
            float secondary;
            switch (direction) {
                case UP:
                    if (dy >= -4) continue;
                    primary = -dy; secondary = Math.abs(dx); break;
                case DOWN:
                    if (dy <= 4) continue;
                    primary = dy; secondary = Math.abs(dx); break;
                case LEFT:
                    if (dx >= -4) continue;
                    primary = -dx; secondary = Math.abs(dy); break;
                default:
                    if (dx <= 4) continue;
                    primary = dx; secondary = Math.abs(dy); break;
            }
            double score = primary * primary + 2.4 * secondary * secondary;
            if (score < bestScore) {
                bestScore = score;
                best = n;
            }
        }

        if (best != null) {
            focusNode(best);
        } else if (direction == Direction.DOWN || direction == Direction.UP) {
            scrollAny(root, direction == Direction.DOWN
                    ? AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
                    : AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD);
        }
    }

    private void clickFocused() {
        AccessibilityNodeInfo root = getRootInActiveWindow();
        if (!isXuperRoot(root)) return;
        AccessibilityNodeInfo node = root.findFocus(AccessibilityNodeInfo.FOCUS_ACCESSIBILITY);
        if (node == null) node = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT);
        if (node == null) {
            List<AccessibilityNodeInfo> nodes = new ArrayList<>();
            collectCandidates(root, nodes, 0);
            node = nearestToScreenCenter(nodes);
            if (node == null) return;
        }
        AccessibilityNodeInfo clickable = node;
        for (int i = 0; i < 6 && clickable != null; i++) {
            if (clickable.isClickable() && clickable.performAction(AccessibilityNodeInfo.ACTION_CLICK)) return;
            clickable = clickable.getParent();
        }
        node.performAction(AccessibilityNodeInfo.ACTION_CLICK);
    }

    private boolean isXuperRoot(AccessibilityNodeInfo root) {
        return root != null && root.getPackageName() != null && XUPER_PACKAGE.contentEquals(root.getPackageName());
    }

    private void collectCandidates(AccessibilityNodeInfo node, List<AccessibilityNodeInfo> out, int depth) {
        if (node == null || depth > 40 || out.size() > 600) return;
        Rect r = new Rect();
        node.getBoundsInScreen(r);
        if (node.isVisibleToUser() && !r.isEmpty() && (node.isFocusable() || node.isClickable())) {
            out.add(node);
        }
        for (int i = 0; i < node.getChildCount(); i++) {
            collectCandidates(node.getChild(i), out, depth + 1);
        }
    }

    private AccessibilityNodeInfo nearestToScreenCenter(List<AccessibilityNodeInfo> nodes) {
        if (nodes == null || nodes.isEmpty()) return null;
        int sw = getResources().getDisplayMetrics().widthPixels;
        int sh = getResources().getDisplayMetrics().heightPixels;
        float cx = sw / 2f, cy = sh / 2f;
        AccessibilityNodeInfo best = null;
        double score = Double.MAX_VALUE;
        for (AccessibilityNodeInfo n : nodes) {
            Rect r = new Rect();
            n.getBoundsInScreen(r);
            double dx = r.exactCenterX() - cx;
            double dy = r.exactCenterY() - cy;
            double s = dx * dx + dy * dy;
            if (s < score) { score = s; best = n; }
        }
        return best;
    }

    private void focusNode(AccessibilityNodeInfo node) {
        if (node == null) return;
        node.performAction(AccessibilityNodeInfo.ACTION_ACCESSIBILITY_FOCUS);
        node.performAction(AccessibilityNodeInfo.ACTION_FOCUS);
    }

    private boolean scrollAny(AccessibilityNodeInfo node, int action) {
        if (node == null) return false;
        if (node.isScrollable() && node.performAction(action)) return true;
        for (int i = 0; i < node.getChildCount(); i++) {
            if (scrollAny(node.getChild(i), action)) return true;
        }
        return false;
    }

    private int dp(int v) {
        return Math.round(v * getResources().getDisplayMetrics().density);
    }
}
