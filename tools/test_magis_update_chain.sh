#!/usr/bin/env bash
set -euo pipefail

PKG='com.msandroid.mobile'
ACTIVITY='com.mobile.brasiltv.activity.SplashAty'
COMPONENT="$PKG/$ACTIVITY"
OUT='diagnostics-update'
mkdir -p "$OUT"

run_timeout() { local secs="$1"; shift; timeout "$secs" "$@"; }

version_code() {
  adb shell dumpsys package "$PKG" 2>/dev/null | sed -n 's/.*versionCode=\([0-9]*\).*/\1/p' | head -1 | tr -d '\r'
}

version_name() {
  adb shell dumpsys package "$PKG" 2>/dev/null | sed -n 's/.*versionName=\(.*\)/\1/p' | head -1 | tr -d '\r'
}

dump_ui() {
  local tag="$1"
  local remote="/sdcard/ui-${tag}.xml"
  run_timeout 10s adb shell uiautomator dump "$remote" >/dev/null 2>&1 || true
  run_timeout 10s adb pull "$remote" "$OUT/ui-${tag}.xml" >/dev/null 2>&1 || true
  run_timeout 10s adb exec-out screencap -p > "$OUT/screen-${tag}.png" || true
  adb shell dumpsys window windows | grep -E 'mCurrentFocus|mFocusedApp' | head -8 > "$OUT/focus-${tag}.txt" || true
}

# Prints x y for the first visible node whose text exactly matches or contains the supplied text.
find_text_center() {
  local xml="$1" text="$2" mode="${3:-exact}"
  python3 - "$xml" "$text" "$mode" <<'PY'
import re, sys, xml.etree.ElementTree as ET
path, needle, mode=sys.argv[1:]
try: root=ET.parse(path).getroot()
except Exception: raise SystemExit(1)
needle=needle.casefold()
for n in root.iter('node'):
    t=(n.attrib.get('text') or n.attrib.get('content-desc') or '').strip()
    if not t: continue
    ok=(t.casefold()==needle) if mode=='exact' else (needle in t.casefold())
    if not ok: continue
    m=re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', n.attrib.get('bounds',''))
    if not m: continue
    x1,y1,x2,y2=map(int,m.groups())
    print((x1+x2)//2,(y1+y2)//2)
    raise SystemExit(0)
raise SystemExit(1)
PY
}

click_text() {
  local tag="$1" text="$2" mode="${3:-exact}"
  dump_ui "$tag"
  local xy
  xy=$(find_text_center "$OUT/ui-${tag}.xml" "$text" "$mode" 2>/dev/null || true)
  [[ -n "$xy" ]] || return 1
  echo "tap [$text] at $xy" | tee -a "$OUT/actions.txt"
  adb shell input tap $xy
}

handle_android_installer() {
  local cycle="$1"
  # Only act on Android's installer/settings surfaces, never arbitrary third-party UI.
  for n in $(seq 1 18); do
    sleep 3
    local tag="c${cycle}-sys${n}"
    dump_ui "$tag"
    local focus
    focus=$(cat "$OUT/focus-${tag}.txt" 2>/dev/null || true)
    local xml="$OUT/ui-${tag}.xml"

    # Android package installer confirmation.
    if echo "$focus" | grep -Eqi 'packageinstaller|permissioncontroller'; then
      for label in Update Install 'Install anyway' Allow OK; do
        local xy
        xy=$(find_text_center "$xml" "$label" exact 2>/dev/null || true)
        if [[ -n "$xy" ]]; then
          echo "system tap [$label] at $xy" | tee -a "$OUT/actions.txt"
          adb shell input tap $xy
          sleep 3
          break
        fi
      done
    fi

    # If the update has already changed the package version, stop handling installer UI.
    local now
    now=$(version_code || true)
    if [[ -n "${BEFORE_CODE:-}" && -n "$now" && "$now" != "$BEFORE_CODE" ]]; then
      return 0
    fi
  done
  return 0
}

echo '=== Install original signed bootstrap APK ===' | tee "$OUT/actions.txt"
run_timeout 45s adb install -r -g magis-current.apk | tee "$OUT/install-bootstrap.txt"
# Equivalent to enabling "Allow from this source" for the app's own updater on the test device.
adb shell appops set "$PKG" REQUEST_INSTALL_PACKAGES allow >/dev/null 2>&1 || true
for perm in android.permission.POST_NOTIFICATIONS android.permission.READ_MEDIA_AUDIO android.permission.READ_MEDIA_IMAGES android.permission.CAMERA; do
  adb shell pm grant "$PKG" "$perm" >/dev/null 2>&1 || true
done

APKSIGNER=$(find "$ANDROID_HOME/build-tools" -type f -name apksigner | sort -V | tail -1)
EXPECTED_CERT=$($APKSIGNER verify --print-certs magis-current.apk 2>/dev/null | sed -n 's/.*certificate SHA-256 digest: //p' | head -1 | tr -d ':[:space:]' | tr '[:upper:]' '[:lower:]')
echo "expected_cert=$EXPECTED_CERT" | tee "$OUT/expected-cert.txt"

for cycle in 1 2 3 4; do
  echo "=== update cycle $cycle ===" | tee -a "$OUT/actions.txt"
  adb shell am force-stop "$PKG" || true
  adb logcat -c || true
  run_timeout 20s adb shell am start -W -n "$COMPONENT" > "$OUT/start-c${cycle}.txt" 2>&1 || true
  sleep 15

  BEFORE_CODE=$(version_code || true)
  BEFORE_NAME=$(version_name || true)
  echo "cycle=$cycle before_code=$BEFORE_CODE before_name=$BEFORE_NAME" | tee -a "$OUT/versions.txt"
  dump_ui "c${cycle}-before"

  # Record visible text for audit/debugging.
  python3 - "$OUT/ui-c${cycle}-before.xml" >> "$OUT/visible-text.txt" <<'PY'
import sys, xml.etree.ElementTree as ET
print('\nFILE',sys.argv[1])
try: root=ET.parse(sys.argv[1]).getroot()
except Exception as e:
    print('parse error',e); raise SystemExit
for n in root.iter('node'):
    t=(n.attrib.get('text') or n.attrib.get('content-desc') or '').strip()
    if t: print(t)
PY

  # The application exposes its official updater through a button literally labelled Update.
  # If no such button is visible, this version has reached a non-update screen and the chain ends.
  if ! click_text "c${cycle}-update-button" Update exact; then
    echo "cycle=$cycle no_update_button" | tee -a "$OUT/actions.txt"
    break
  fi

  # Give the app time to download/launch its own update and then cooperate with Android's normal installer.
  handle_android_installer "$cycle"

  UPDATED=0
  for n in $(seq 1 30); do
    sleep 4
    NOW_CODE=$(version_code || true)
    if [[ -n "$NOW_CODE" && -n "$BEFORE_CODE" && "$NOW_CODE" != "$BEFORE_CODE" ]]; then
      UPDATED=1
      break
    fi
  done

  NOW_CODE=$(version_code || true)
  NOW_NAME=$(version_name || true)
  echo "cycle=$cycle after_code=$NOW_CODE after_name=$NOW_NAME updated=$UPDATED" | tee -a "$OUT/versions.txt"
  dump_ui "c${cycle}-after"

  if [[ "$UPDATED" != 1 ]]; then
    echo "cycle=$cycle UPDATE_DID_NOT_INSTALL" | tee -a "$OUT/actions.txt"
    break
  fi

  # Pull the exact package Android installed and verify it stayed in the original signing lineage.
  APK_PATH=$(adb shell pm path "$PKG" | sed -n 's/^package://p' | head -1 | tr -d '\r')
  echo "cycle=$cycle installed_path=$APK_PATH" | tee -a "$OUT/versions.txt"
  if [[ -n "$APK_PATH" ]]; then
    run_timeout 30s adb pull "$APK_PATH" "$OUT/magis-after-cycle-${cycle}.apk" >/dev/null 2>&1 || true
    if [[ -s "$OUT/magis-after-cycle-${cycle}.apk" ]]; then
      CERT=$($APKSIGNER verify --print-certs "$OUT/magis-after-cycle-${cycle}.apk" 2>/dev/null | sed -n 's/.*certificate SHA-256 digest: //p' | head -1 | tr -d ':[:space:]' | tr '[:upper:]' '[:lower:]')
      echo "cycle=$cycle cert=$CERT" | tee -a "$OUT/certificates.txt"
      if [[ -n "$EXPECTED_CERT" && "$CERT" != "$EXPECTED_CERT" ]]; then
        echo 'SIGNER_CHANGED_ABORT' >&2
        exit 31
      fi
    fi
  fi

done

# Final stability check on whichever legitimate version the official update flow reached.
adb shell am force-stop "$PKG" || true
run_timeout 20s adb shell am start -W -n "$COMPONENT" > "$OUT/start-final.txt" 2>&1 || true
sleep 20
FINAL_PID20=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true)
FINAL_CODE=$(version_code || true)
FINAL_NAME=$(version_name || true)
echo "final_code=$FINAL_CODE final_name=$FINAL_NAME pid20=${FINAL_PID20:-DEAD}" | tee "$OUT/final.txt"
dump_ui final20
sleep 30
FINAL_PID50=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true)
echo "pid50=${FINAL_PID50:-DEAD}" | tee -a "$OUT/final.txt"
dump_ui final50
adb logcat -d -v threadtime | grep -Ei 'com\.msandroid\.mobile|FATAL EXCEPTION|AndroidRuntime|SIGKILL|EXIT_SELF|UnsatisfiedLinkError' | tail -1200 > "$OUT/logcat-final.txt" || true

# Always export the currently installed signed APK as the final candidate.
FINAL_APK_PATH=$(adb shell pm path "$PKG" | sed -n 's/^package://p' | head -1 | tr -d '\r')
if [[ -n "$FINAL_APK_PATH" ]]; then
  run_timeout 30s adb pull "$FINAL_APK_PATH" "$OUT/Magis-Mobile-Final-Tested.apk" >/dev/null 2>&1 || true
fi

[[ -n "$FINAL_PID20" && -n "$FINAL_PID50" ]] || { echo 'FINAL_RUNTIME_FAIL' >&2; exit 40; }
[[ -s "$OUT/Magis-Mobile-Final-Tested.apk" ]] || { echo 'FINAL_APK_PULL_FAIL' >&2; exit 41; }
FINAL_CERT=$($APKSIGNER verify --print-certs "$OUT/Magis-Mobile-Final-Tested.apk" 2>/dev/null | sed -n 's/.*certificate SHA-256 digest: //p' | head -1 | tr -d ':[:space:]' | tr '[:upper:]' '[:lower:]')
echo "final_cert=$FINAL_CERT" | tee -a "$OUT/final.txt"
[[ "$FINAL_CERT" == "$EXPECTED_CERT" ]] || { echo 'FINAL_SIGNER_MISMATCH' >&2; exit 42; }

echo 'MAGIS_UPDATE_CHAIN_TEST_OK'
