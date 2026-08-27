#!/usr/bin/env bash
set -u

PKG='com.android.mgstv'
ACT='com.interactive.brasiliptv.ui.activity.WelcomeActivity'
OUT='diagnostics-v3'
mkdir -p "$OUT"

adb install -r base.apk
adb shell settings put secure immersive_mode_confirmations confirmed >/dev/null 2>&1 || true

reset_display() {
  adb shell am compat reset-all "$PKG" >/dev/null 2>&1 || true
  adb shell wm reset >/dev/null 2>&1 || true
  adb shell wm set-ignore-orientation-request false >/dev/null 2>&1 || true
  adb shell settings put system accelerometer_rotation 0 >/dev/null 2>&1 || true
  adb shell settings put system user_rotation 1 >/dev/null 2>&1 || true
  adb shell wm user-rotation lock 1 >/dev/null 2>&1 || true
  sleep 1
}

compat_enable() {
  local name="$1" tag="$2"
  adb shell am compat enable "$name" "$PKG" > "$OUT/${tag}-${name}.txt" 2>&1 || true
}

capture() {
  local name="$1"
  adb shell am force-stop "$PKG" >/dev/null 2>&1 || true
  adb shell am start -W -n "$PKG/$ACT" > "$OUT/${name}-start.txt" 2>&1 || true
  sleep 10
  adb exec-out screencap -p > "$OUT/${name}.png" || true
  adb shell uiautomator dump /sdcard/xuper-v3.xml >/dev/null 2>&1 || true
  adb pull /sdcard/xuper-v3.xml "$OUT/${name}-ui.xml" >/dev/null 2>&1 || true
  adb shell dumpsys window displays > "$OUT/${name}-window.txt" 2>&1 || true
  adb shell dumpsys activity activities | grep -E 'mResumedActivity|topResumedActivity' > "$OUT/${name}-focus.txt" || true
  local pid
  pid=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true)
  local size density
  size=$(adb shell wm size 2>/dev/null | tr -d '\r' | tail -1)
  density=$(adb shell wm density 2>/dev/null | tr -d '\r' | tail -1)
  printf '%-34s pid=%-8s | %s | %s\n' "$name" "${pid:-DEAD}" "$size" "$density" | tee -a "$OUT/results.txt"
}

# 1) Reference: untouched APK in its normal landscape behavior.
reset_display
capture baseline_landscape

# 2) Ask Android to treat the app as resizable while leaving its APK/signature untouched.
reset_display
compat_enable FORCE_RESIZE_APP force_resize
capture force_resize_landscape

# 3) Android orientation override, without editing the manifest.
reset_display
compat_enable FORCE_RESIZE_APP portrait_user
compat_enable OVERRIDE_ANY_ORIENTATION_TO_USER portrait_user
compat_enable OVERRIDE_LANDSCAPE_ORIENTATION_TO_USER portrait_user
adb shell wm set-ignore-orientation-request true >/dev/null 2>&1 || true
adb shell settings put system user_rotation 0 >/dev/null 2>&1 || true
adb shell wm user-rotation lock 0 >/dev/null 2>&1 || true
capture portrait_force_resize

# 4) Same portrait mode, but render fewer logical pixels first so TV-sized widgets
# have a better chance of fitting a phone viewport.
for scale in 70 60; do
  reset_display
  compat_enable FORCE_RESIZE_APP "portrait_${scale}"
  compat_enable OVERRIDE_ANY_ORIENTATION_TO_USER "portrait_${scale}"
  compat_enable OVERRIDE_LANDSCAPE_ORIENTATION_TO_USER "portrait_${scale}"
  compat_enable DOWNSCALED "portrait_${scale}"
  compat_enable "DOWNSCALE_${scale}" "portrait_${scale}"
  adb shell wm set-ignore-orientation-request true >/dev/null 2>&1 || true
  adb shell settings put system user_rotation 0 >/dev/null 2>&1 || true
  adb shell wm user-rotation lock 0 >/dev/null 2>&1 || true
  capture "portrait_downscale_${scale}"
done

# 5) Density experiments. Xuper advertises a 1280dp TV design width; a low logical
# density lets more dp fit across the physical phone width without repacking the APK.
for dpi in 180 160 140; do
  reset_display
  compat_enable FORCE_RESIZE_APP "density_${dpi}"
  compat_enable OVERRIDE_ANY_ORIENTATION_TO_USER "density_${dpi}"
  compat_enable OVERRIDE_LANDSCAPE_ORIENTATION_TO_USER "density_${dpi}"
  adb shell wm density "$dpi" >/dev/null 2>&1 || true
  adb shell wm set-ignore-orientation-request true >/dev/null 2>&1 || true
  adb shell settings put system user_rotation 0 >/dev/null 2>&1 || true
  adb shell wm user-rotation lock 0 >/dev/null 2>&1 || true
  capture "portrait_density_${dpi}"
done

# 6) Best stable landscape scale from the previous round, kept as a comparison.
reset_display
compat_enable DOWNSCALED landscape_70
compat_enable DOWNSCALE_70 landscape_70
capture landscape_downscale_70

reset_display
cat "$OUT/results.txt"
