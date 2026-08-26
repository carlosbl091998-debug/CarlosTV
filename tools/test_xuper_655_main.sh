#!/usr/bin/env bash
set -euo pipefail

PKG='com.msandroid.mobile'
OUT='diagnostics-update'
TARGET_CODE='60505'
TARGET_NAME='6.5.5'
mkdir -p "$OUT/candidates"

SOURCES=(
  'https://gaeg.xvmobdes.com/download'
  'https://aftvnews.com/3154861'
  'https://www.aftvnews.com/3154861'
  'https://go.aftvnews.com/3154861'
  'https://tvxuper.com/download/'
  'https://apkdownloader.cc/storage/files/2026/03/xuper-tv-6-5-5_1774679197.apk'
)

run_timeout() { local secs="$1"; shift; timeout "$secs" "$@"; }
version_code() { adb shell dumpsys package "$PKG" 2>/dev/null | sed -n 's/.*versionCode=\([0-9]*\).*/\1/p' | head -1 | tr -d '\r'; }
version_name() { adb shell dumpsys package "$PKG" 2>/dev/null | sed -n 's/.*versionName=\(.*\)/\1/p' | head -1 | tr -d '\r'; }

launch_app() {
  adb shell am force-stop "$PKG" >/dev/null 2>&1 || true
  run_timeout 20s adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
}

dump_ui() {
  local tag="$1" remote="/sdcard/ui-${1}.xml"
  run_timeout 10s adb shell uiautomator dump "$remote" >/dev/null 2>&1 || true
  run_timeout 10s adb pull "$remote" "$OUT/ui-${tag}.xml" >/dev/null 2>&1 || true
  run_timeout 10s adb exec-out screencap -p > "$OUT/screen-${tag}.png" || true
}

xml_has() {
  local xml="$1" needle="$2"
  python3 - "$xml" "$needle" <<'PY'
import sys, xml.etree.ElementTree as ET
try:
    root=ET.parse(sys.argv[1]).getroot()
except Exception:
    raise SystemExit(1)
needle=sys.argv[2].casefold()
text='\n'.join((n.attrib.get('text','')+' '+n.attrib.get('content-desc','')) for n in root.iter('node')).casefold()
raise SystemExit(0 if needle in text else 1)
PY
}

is_update_gate() {
  local xml="$1"
  xml_has "$xml" 'Actualización de versión' || \
  xml_has "$xml" 'Version Upgrade' || \
  xml_has "$xml" 'V6.5.5' || \
  xml_has "$xml" 'Current version:' || \
  xml_has "$xml" 'Versión actual:'
}

AAPT=$(find "$ANDROID_HOME/build-tools" -type f -name aapt | sort -V | tail -1)
APKSIGNER=$(find "$ANDROID_HOME/build-tools" -type f -name apksigner | sort -V | tail -1)

echo '=== install known official signed bootstrap ===' | tee "$OUT/actions.txt"
run_timeout 45s adb install -r -g magis-current.apk | tee "$OUT/install-bootstrap.txt"
EXPECTED_CERT=$($APKSIGNER verify --print-certs magis-current.apk 2>/dev/null | sed -n 's/.*certificate SHA-256 digest: //p' | head -1 | tr -d ':[:space:]' | tr '[:upper:]' '[:lower:]')
echo "expected_cert=$EXPECTED_CERT" | tee "$OUT/expected-cert.txt"
[[ -n "$EXPECTED_CERT" ]] || { echo 'BOOTSTRAP_CERT_NOT_FOUND' >&2; exit 60; }

launch_app
sleep 15
dump_ui bootstrap-before-update
echo "bootstrap_code=$(version_code || true) bootstrap_name=$(version_name || true)" | tee "$OUT/bootstrap-version.txt"

validate_apk() {
  local f="$1" tag="$2"
  unzip -t "$f" >/dev/null 2>&1 || return 1
  "$AAPT" dump badging "$f" > "$OUT/candidates/${tag}-badging.txt" 2>&1 || return 1
  grep -q "package: name='$PKG' versionCode='$TARGET_CODE' versionName='$TARGET_NAME'" "$OUT/candidates/${tag}-badging.txt" || return 1
  "$APKSIGNER" verify --verbose --print-certs "$f" > "$OUT/candidates/${tag}-signing.txt" 2>&1 || return 1
  local cert
  cert=$($APKSIGNER verify --print-certs "$f" 2>/dev/null | sed -n 's/.*certificate SHA-256 digest: //p' | head -1 | tr -d ':[:space:]' | tr '[:upper:]' '[:lower:]')
  echo "$cert" > "$OUT/candidates/${tag}-cert.txt"
  [[ "$cert" == "$EXPECTED_CERT" ]] || return 1
  sha256sum "$f" > "$OUT/candidates/${tag}-sha256.txt"
  return 0
}

extract_links() {
  local f="$1" base="$2" out="$3"
  python3 - "$f" "$base" > "$out" <<'PY' || true
import html, re, sys
from urllib.parse import urljoin
p, base=sys.argv[1], sys.argv[2]
raw=open(p,'rb').read(4_000_000).decode('utf-8','ignore')
raw=html.unescape(raw).replace('\\/','/')
links=[]
for pat in [
    r'https?://[^\"\'<>\s]+',
    r'(?:href|src)\s*=\s*[\"\']([^\"\']+)[\"\']',
]:
    for m in re.finditer(pat, raw, re.I):
        u=m.group(1) if m.lastindex else m.group(0)
        u=urljoin(base,u)
        if u.startswith('http') and u not in links:
            links.append(u)
links.sort(key=lambda u: (0 if any(k in u.lower() for k in ('.apk','download','3154861','xuper')) else 1, len(u)))
for u in links[:20]: print(u)
PY
}

FINAL_SOURCE=''
TARGET_APK="$OUT/Xuper-6.5.5-Downloaded.apk"
rm -f "$TARGET_APK"

for i in "${!SOURCES[@]}"; do
  src="${SOURCES[$i]}"
  tag="source-$((i+1))"
  f="$OUT/candidates/${tag}.bin"
  echo "TRY $tag $src" | tee -a "$OUT/actions.txt"

  if ! curl -fL --retry 3 --retry-all-errors --connect-timeout 20 --max-time 180 \
      -A 'Mozilla/5.0 (Linux; Android 16; Pixel 6) AppleWebKit/537.36 Chrome/140 Mobile Safari/537.36' \
      -e 'https://aftvnews.com/' \
      -D "$OUT/candidates/${tag}-headers.txt" \
      -w '%{url_effective}\n%{http_code}\n%{content_type}\n' \
      "$src" -o "$f" > "$OUT/candidates/${tag}-meta.txt" 2> "$OUT/candidates/${tag}-curl.txt"; then
    echo "$tag curl_failed" | tee -a "$OUT/actions.txt"
    continue
  fi

  file "$f" > "$OUT/candidates/${tag}-file.txt" || true
  ls -lh "$f" > "$OUT/candidates/${tag}-size.txt" || true

  if validate_apk "$f" "$tag"; then
    cp "$f" "$TARGET_APK"
    FINAL_SOURCE="$src"
    echo "ACCEPTED_DIRECT $tag $src" | tee -a "$OUT/actions.txt"
    break
  fi

  links="$OUT/candidates/${tag}-links.txt"
  extract_links "$f" "$src" "$links"
  n=0
  while IFS= read -r nested; do
    [[ -n "$nested" ]] || continue
    n=$((n+1))
    [[ $n -le 12 ]] || break
    nf="$OUT/candidates/${tag}-nested-${n}.bin"
    echo "TRY_NESTED $tag#$n $nested" | tee -a "$OUT/actions.txt"
    if curl -fL --retry 2 --retry-all-errors --connect-timeout 15 --max-time 180 \
        -A 'Mozilla/5.0 (Linux; Android 16; Pixel 6)' -e "$src" \
        "$nested" -o "$nf" > /dev/null 2> "$OUT/candidates/${tag}-nested-${n}-curl.txt"; then
      if validate_apk "$nf" "${tag}-nested-${n}"; then
        cp "$nf" "$TARGET_APK"
        FINAL_SOURCE="$nested"
        echo "ACCEPTED_NESTED $tag#$n $nested" | tee -a "$OUT/actions.txt"
        break 2
      fi
    fi
  done < "$links"
done

[[ -s "$TARGET_APK" ]] || {
  echo 'NO_CANDIDATE_MATCHED_PACKAGE_VERSION_AND_OFFICIAL_CERT' >&2
  exit 61
}

echo "final_source=$FINAL_SOURCE" | tee "$OUT/final-source.txt"
"$AAPT" dump badging "$TARGET_APK" | tee "$OUT/downloaded-badging.txt"
"$APKSIGNER" verify --verbose --print-certs "$TARGET_APK" | tee "$OUT/downloaded-signing.txt"
sha256sum "$TARGET_APK" | tee "$OUT/downloaded-sha256.txt"

echo '=== adb install -r verified official 6.5.5 ===' | tee -a "$OUT/actions.txt"
run_timeout 90s adb install -r -g "$TARGET_APK" | tee "$OUT/install-655.txt"
FINAL_CODE=$(version_code || true)
FINAL_NAME=$(version_name || true)
echo "installed_code=$FINAL_CODE installed_name=$FINAL_NAME" | tee "$OUT/final.txt"
[[ "$FINAL_CODE" == "$TARGET_CODE" && "$FINAL_NAME" == "$TARGET_NAME" ]] || {
  echo 'ANDROID_UPDATE_DID_NOT_REACH_655' >&2; exit 64;
}

adb emu geo fix -99.1332 19.4326 >/dev/null 2>&1 || true
launch_app
sleep 20
PID20=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true)
dump_ui final20
sleep 40
PID60=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true)
dump_ui final60
echo "pid20=${PID20:-DEAD} pid60=${PID60:-DEAD}" | tee -a "$OUT/final.txt"
[[ -n "$PID20" && -n "$PID60" ]] || { echo 'FINAL_RUNTIME_FAIL' >&2; exit 65; }

if is_update_gate "$OUT/ui-final20.xml" || is_update_gate "$OUT/ui-final60.xml"; then
  echo 'FINAL_UPDATE_GATE_STILL_PRESENT' >&2
  exit 66
fi

APK_PATH=$(adb shell pm path "$PKG" | sed -n 's/^package://p' | head -1 | tr -d '\r')
run_timeout 30s adb pull "$APK_PATH" "$OUT/Xuper-6.5.5-Final-Tested.apk" >/dev/null
FINAL_CERT=$($APKSIGNER verify --print-certs "$OUT/Xuper-6.5.5-Final-Tested.apk" 2>/dev/null | sed -n 's/.*certificate SHA-256 digest: //p' | head -1 | tr -d ':[:space:]' | tr '[:upper:]' '[:lower:]')
echo "final_cert=$FINAL_CERT" | tee -a "$OUT/final.txt"
[[ "$FINAL_CERT" == "$EXPECTED_CERT" ]] || { echo 'FINAL_SIGNER_MISMATCH' >&2; exit 67; }
sha256sum "$OUT/Xuper-6.5.5-Final-Tested.apk" | tee "$OUT/final-sha256.txt"
adb logcat -d -v threadtime | grep -Ei 'com\.msandroid\.mobile|FATAL EXCEPTION|AndroidRuntime|SIGKILL|EXIT_SELF|UnsatisfiedLinkError' | tail -1200 > "$OUT/logcat-final.txt" || true

echo 'XUPER_655_OFFICIAL_UPDATE_RUNTIME_NO_UPDATE_GATE_OK'
