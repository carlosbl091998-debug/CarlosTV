#!/usr/bin/env bash
set -euo pipefail

PKG='com.msandroid.mobile'

# Android 16 can stop Magis at runtime permission dialogs before the app reaches
# its own update logic. Keep granting only ordinary app runtime permissions
# while the actual 6.2.4 test script installs/clears/restarts the package.
(
  for _ in $(seq 1 240); do
    if adb shell pm path "$PKG" >/dev/null 2>&1; then
      adb shell pm grant "$PKG" android.permission.READ_MEDIA_AUDIO >/dev/null 2>&1 || true
      adb shell pm grant "$PKG" android.permission.READ_MEDIA_IMAGES >/dev/null 2>&1 || true
      adb shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true
      adb shell pm grant "$PKG" android.permission.CAMERA >/dev/null 2>&1 || true
      adb shell pm grant "$PKG" android.permission.READ_EXTERNAL_STORAGE >/dev/null 2>&1 || true

      # Fallback for a permission-controller window that was already created
      # before pm grant completed. Tap only when Android's permission controller
      # is the focused window, never inside Magis itself.
      FOCUS=$(adb shell dumpsys window windows 2>/dev/null | grep -E 'mCurrentFocus|mFocusedApp' | tail -2 || true)
      if echo "$FOCUS" | grep -qi 'permissioncontroller'; then
        adb shell input tap 540 1325 >/dev/null 2>&1 || true
      fi
    fi
    sleep 1
  done
) &
WATCHER=$!
trap 'kill "$WATCHER" >/dev/null 2>&1 || true' EXIT

bash tools/test_xuper_655_main.sh
