#!/usr/bin/env bash
set -u

PKG='com.android.mgstv'
ACT='com.interactive.brasiliptv.ui.activity.WelcomeActivity'
mkdir -p diagnostics

adb install -r base.apk

# Grant common runtime permissions where Android permits it so system dialogs
# do not obscure the UI screenshots.
for p in \
  android.permission.READ_PHONE_STATE \
  android.permission.READ_PHONE_NUMBERS \
  android.permission.POST_NOTIFICATIONS \
  android.permission.ACCESS_FINE_LOCATION \
  android.permission.ACCESS_COARSE_LOCATION \
  android.permission.READ_MEDIA_IMAGES \
  android.permission.READ_MEDIA_VIDEO \
  android.permission.RECORD_AUDIO
do
  adb shell pm grant "$PKG" "$p" >/dev/null 2>&1 || true
done

capture() {
  local name="$1"
  adb shell am force-stop "$PKG" || true
  adb shell am start -W -n "$PKG/$ACT" > "diagnostics/${name}-start.txt" 2>&1 || true
  sleep 10
  adb exec-out screencap -p > "diagnostics/${name}.png" || true
  adb shell uiautomator dump /sdcard/window.xml >/dev/null 2>&1 || true
  adb pull /sdcard/window.xml "diagnostics/${name}-ui.xml" >/dev/null 2>&1 || true
  adb shell dumpsys window windows | grep -E 'mCurrentFocus|mFocusedApp' > "diagnostics/${name}-focus.txt" || true
  local pid
  pid=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true)
  printf '%s pid=%s\n' "$name" "${pid:-DEAD}" | tee -a diagnostics/results.txt
}

# Baseline untouched APK.
adb shell am compat reset-all "$PKG" >/dev/null 2>&1 || true
adb shell settings put system accelerometer_rotation 0
adb shell settings put system user_rotation 1
capture baseline_landscape

# Android system resize override, APK remains untouched.
adb shell am compat enable FORCE_RESIZE_APP "$PKG" || true
capture force_resize_landscape

# Let user/device orientation override the TV app and test portrait.
adb shell am compat enable OVERRIDE_ANY_ORIENTATION_TO_USER "$PKG" || true
adb shell settings put system user_rotation 0
capture resize_user_portrait

# Try full portrait surface / aspect-ratio compatibility.
adb shell am compat enable OVERRIDE_MIN_ASPECT_RATIO "$PKG" || true
adb shell am compat enable OVERRIDE_MIN_ASPECT_RATIO_EXCLUDE_PORTRAIT_FULLSCREEN "$PKG" || true
capture resize_portrait_fullscreen

cat diagnostics/results.txt
