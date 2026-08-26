#!/usr/bin/env bash
set -euo pipefail

PKG='com.msandroid.mobile'
BOOT_ACTIVITY='com.mobile.brasiltv.activity.SplashAty'
OUT='diagnostics-update'
mkdir -p "$OUT"

run_timeout() { local secs="$1"; shift; timeout "$secs" "$@"; }
version_code() { adb shell dumpsys package "$PKG" 2>/dev/null | sed -n 's/.*versionCode=\([0-9]*\).*/\1/p' | head -1 | tr -d '\r'; }
version_name() { adb shell dumpsys package "$PKG" 2>/dev/null | sed -n 's/.*versionName=\(.*\)/\1/p' | head -1 | tr -d '\r'; }

grant_common_permissions() {
  for perm in \
    android.permission.POST_NOTIFICATIONS \
    android.permission.READ_MEDIA_AUDIO \
    android.permission.READ_MEDIA_IMAGES \
    android.permission.CAMERA \
    android.permission.RECORD_AUDIO; do
    adb shell pm grant "$PKG" "$perm" >/dev/null 2>&1 || true
  done
}

launch_app() {
  adb shell am force-stop "$PKG" >/dev/null 2>&1 || true
  # Use the package launcher so this continues to work if the successor changes activity names.
  run_timeout 20s adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || \
    run_timeout 20s adb shell am start -W -n "$PKG/$BOOT_ACTIVITY" >/dev/null 2>&1 || true
}

dump_ui() {
  local tag="$1" remote="/sdcard/ui-${1}.xml"
  run_timeout 10s adb shell uiautomator dump "$remote" >/dev/null 2>&1 || true
  run_timeout 10s adb pull "$remote" "$OUT/ui-${tag}.xml" >/dev/null 2>&1 || true
  run_timeout 10s adb exec-out screencap -p > "$OUT/screen-${tag}.png" || true
  adb shell dumpsys activity activities | grep -E 'mResumedActivity|topResumedActivity|ResumedActivity' | head -8 > "$OUT/focus-${tag}.txt" || true
}

find_text_center() {
  local xml="$1" text="$2" mode="${3:-exact}"
  python3 - "$xml" "$text" "$mode" <<'PY'
import re, sys, xml.etree.ElementTree as ET
path, needle, mode=sys.argv[1:]
try: root=ET.parse(path).getroot()
except Exception: raise SystemExit(1)
needle=needle.casefold()
for n in root.iter('node'):
    vals=[n.attrib.get('text',''), n.attrib.get('content-desc','')]
    for raw in vals:
        t=(raw or '').strip()
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

xml_contains() {
  local xml="$1" needle="$2"
  python3 - "$xml" "$needle" <<'PY'
import sys, xml.etree.ElementTree as ET
try: root=ET.parse(sys.argv[1]).getroot()
except Exception: raise SystemExit(1)
n=sys.argv[2].casefold()
text='\n'.join((x.attrib.get('text','')+' '+x.attrib.get('content-desc','')) for x in root.iter('node')).casefold()
raise SystemExit(0 if n in text else 1)
PY
}

click_text_from_xml() {
  local xml="$1" label="$2" mode="${3:-exact}" xy
  xy=$(find_text_center "$xml" "$label" "$mode" 2>/dev/null || true)
  [[ -n "$xy" ]] || return 1
  echo "tap [$label] at $xy" | tee -a "$OUT/actions.txt"
  adb shell input tap $xy
}

handle_android_installer() {
  local cycle="$1"
  for n in $(seq 1 24); do
    sleep 3
    local tag="c${cycle}-sys${n}" xml="$OUT/ui-c${cycle}-sys${n}.xml"
    dump_ui "$tag"

    # Android 16 may not expose PackageInstaller as the focused component in dumpsys.
    # Detect the normal OS confirmation by its visible prompt instead.
    if xml_contains "$xml" 'Do you want to update this app?' 2>/dev/null; then
      echo "cycle=$cycle android_update_confirmation_visible" | tee -a "$OUT/actions.txt"
      click_text_from_xml "$xml" Update exact || true
      sleep 4
    elif xml_contains "$xml" 'Install unknown apps' 2>/dev/null; then
      echo "cycle=$cycle unknown_apps_settings_visible" | tee -a "$OUT/actions.txt"
    elif xml_contains "$xml" 'App installed' 2>/dev/null; then
      echo "cycle=$cycle app_installed_screen_visible" | tee -a "$OUT/actions.txt"
      click_text_from_xml "$xml" Done exact || true
    fi

    local now
    now=$(version_code || true)
    if [[ -n "${BEFORE_CODE:-}" && -n "$now" && "$now" != "$BEFORE_CODE" ]]; then
      echo "cycle=$cycle version_changed_during_installer to=$now" | tee -a "$OUT/actions.txt"
      return 0
    fi
  done
  return 0
}

echo '=== Install original signed bootstrap APK ===' | tee "$OUT/actions.txt"
run_timeout 45s adb install -r -g magis-current.apk | tee "$OUT/install-bootstrap.txt"
adb shell appops set "$PKG" REQUEST_INSTALL_PACKAGES allow >/dev/null 2>&1 || true
grant_common_permissions

APKSIGNER=$(find "$ANDROID_HOME/build-tools" -type f -name apksigner | sort -V | tail -1)
EXPECTED_CERT=$($APKSIGNER verify --print-certs magis-current.apk 2>/dev/null | sed -n 's/.*certificate SHA-256 digest: //p' | head -1 | tr -d ':[:space:]' | tr '[:upper:]' '[:lower:]')
echo "expected_cert=$EXPECTED_CERT" | tee "$OUT/expected-cert.txt"

ANY_UPDATED=0
for cycle in 1 2 3 4; do
  echo "=== update cycle $cycle ===" | tee -a "$OUT/actions.txt"
  launch_app
  sleep 15

  BEFORE_CODE=$(version_code || true)
  BEFORE_NAME=$(version_name || true)
  echo "cycle=$cycle before_code=$BEFORE_CODE before_name=$BEFORE_NAME" | tee -a "$OUT/versions.txt"
  dump_ui "c${cycle}-before"
  XML="$OUT/ui-c${cycle}-before.xml"

  # If the normal app UI is reached, the official update chain is done.
  if ! xml_contains "$XML" 'Version Upgrade' 2>/dev/null && ! xml_contains "$XML" 'discontinued' 2>/dev/null; then
    echo "cycle=$cycle no_mandatory_update_gate" | tee -a "$OUT/actions.txt"
    break
  fi

  if ! click_text_from_xml "$XML" Update exact; then
    echo "cycle=$cycle update_button_not_found" | tee -a "$OUT/actions.txt"
    break
  fi

  handle_android_installer "$cycle"

  UPDATED=0
  for n in $(seq 1 25); do
    sleep 3
    NOW_CODE=$(version_code || true)
    if [[ -n "$NOW_CODE" && -n "$BEFORE_CODE" && "$NOW_CODE" != "$BEFORE_CODE" ]]; then
      UPDATED=1; ANY_UPDATED=1; break
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

  grant_common_permissions
  APK_PATH=$(adb shell pm path "$PKG" | sed -n 's/^package://p' | head -1 | tr -d '\r')
  if [[ -n "$APK_PATH" ]]; then
    run_timeout 30s adb pull "$APK_PATH" "$OUT/magis-after-cycle-${cycle}.apk" >/dev/null 2>&1 || true
    if [[ -s "$OUT/magis-after-cycle-${cycle}.apk" ]]; then
      CERT=$($APKSIGNER verify --print-certs "$OUT/magis-after-cycle-${cycle}.apk" 2>/dev/null | sed -n 's/.*certificate SHA-256 digest: //p' | head -1 | tr -d ':[:space:]' | tr '[:upper:]' '[:lower:]')
      echo "cycle=$cycle cert=$CERT" | tee -a "$OUT/certificates.txt"
      [[ "$CERT" == "$EXPECTED_CERT" ]] || { echo 'SIGNER_CHANGED_ABORT' >&2; exit 31; }
    fi
  fi
done

# A useful result must actually have advanced beyond the obsolete bootstrap.
[[ "$ANY_UPDATED" == 1 ]] || { echo 'NO_OFFICIAL_UPDATE_INSTALLED' >&2; exit 32; }

launch_app
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

FINAL_XML="$OUT/ui-final50.xml"
if xml_contains "$FINAL_XML" 'Version Upgrade' 2>/dev/null || xml_contains "$FINAL_XML" 'discontinued' 2>/dev/null; then
  echo 'FINAL_UPDATE_GATE_STILL_PRESENT' >&2
  exit 43
fi

adb logcat -d -v threadtime | grep -Ei 'com\.msandroid\.mobile|FATAL EXCEPTION|AndroidRuntime|SIGKILL|EXIT_SELF|UnsatisfiedLinkError' | tail -1200 > "$OUT/logcat-final.txt" || true
FINAL_APK_PATH=$(adb shell pm path "$PKG" | sed -n 's/^package://p' | head -1 | tr -d '\r')
if [[ -n "$FINAL_APK_PATH" ]]; then
  run_timeout 30s adb pull "$FINAL_APK_PATH" "$OUT/Magis-Mobile-Final-Tested.apk" >/dev/null 2>&1 || true
fi

[[ -n "$FINAL_PID20" && -n "$FINAL_PID50" ]] || { echo 'FINAL_RUNTIME_FAIL' >&2; exit 40; }
[[ -s "$OUT/Magis-Mobile-Final-Tested.apk" ]] || { echo 'FINAL_APK_PULL_FAIL' >&2; exit 41; }
FINAL_CERT=$($APKSIGNER verify --print-certs "$OUT/Magis-Mobile-Final-Tested.apk" 2>/dev/null | sed -n 's/.*certificate SHA-256 digest: //p' | head -1 | tr -d ':[:space:]' | tr '[:upper:]' '[:lower:]')
echo "final_cert=$FINAL_CERT" | tee -a "$OUT/final.txt"
[[ "$FINAL_CERT" == "$EXPECTED_CERT" ]] || { echo 'FINAL_SIGNER_MISMATCH' >&2; exit 42; }

echo 'MAGIS_OFFICIAL_SUCCESSOR_RUNTIME_OK'
