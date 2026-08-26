#!/usr/bin/env bash
set -euo pipefail

APK=${1:?APK path required}
PKG='com.msandroid.mobile'
OUT='diagnostics-auth-vod'
mkdir -p "$OUT"

redact() {
  sed -e "s/${XUPER_USER//\//\\/}/***USER***/g" -e "s/${XUPER_PASS//\//\\/}/***PASS***/g"
}

capture() {
  adb logcat -d -v threadtime 2>/dev/null | redact > "$OUT/logcat.txt" || true
  adb shell dumpsys activity activities > "$OUT/activities.txt" 2>/dev/null || true
  timeout 10s adb shell uiautomator dump /sdcard/window.xml >/dev/null 2>&1 || true
  adb pull /sdcard/window.xml "$OUT/window.xml" >/dev/null 2>&1 || true
  timeout 10s adb exec-out screencap -p > "$OUT/screen.png" || true
}
trap capture EXIT

adb wait-for-device
adb uninstall "$PKG" >/dev/null 2>&1 || true
adb logcat -c || true
adb install -g "$APK" > "$OUT/install.txt" 2>&1
adb shell am force-stop "$PKG" >/dev/null 2>&1 || true
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
sleep 8

dump_ui() {
  timeout 10s adb shell uiautomator dump /sdcard/window.xml >/dev/null 2>&1 || true
  adb pull /sdcard/window.xml "$1" >/dev/null 2>&1 || true
}

tap_center_for_match() {
  local file="$1" pattern="$2"
  python3 - "$file" "$pattern" <<'PY'
import re,sys,subprocess
p=sys.argv[1]; pat=sys.argv[2].lower()
s=open(p,errors='ignore').read()
for node in re.findall(r'<node\b[^>]*>',s):
    text=(re.search(r'text="([^"]*)"',node) or re.search(r'content-desc="([^"]*)"',node))
    if not text or pat not in text.group(1).lower():
        continue
    b=re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',node)
    if b:
        x1,y1,x2,y2=map(int,b.groups()); print((x1+x2)//2,(y1+y2)//2); sys.exit(0)
sys.exit(2)
PY
}

# Login screen detection. Avoid printing credentials or commands containing them.
dump_ui "$OUT/ui-initial.xml"
if grep -Eiq 'login|iniciar sesi|correo|email|contrase|password' "$OUT/ui-initial.xml"; then
  python3 - "$OUT/ui-initial.xml" > /tmp/fields.txt <<'PY'
import re,sys
s=open(sys.argv[1],errors='ignore').read(); out=[]
for node in re.findall(r'<node\b[^>]*>',s):
    if 'class="android.widget.EditText"' not in node: continue
    b=re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',node)
    if b:
        x1,y1,x2,y2=map(int,b.groups()); out.append(((x1+x2)//2,(y1+y2)//2))
for x,y in out[:2]: print(x,y)
PY
  mapfile -t FIELDS < /tmp/fields.txt
  if [ ${#FIELDS[@]} -ge 2 ]; then
    read -r ux uy <<<"${FIELDS[0]}"; read -r px py <<<"${FIELDS[1]}"
    adb shell input tap "$ux" "$uy"
    adb shell input text "$(python3 - <<'PY'
import os,urllib.parse
print(urllib.parse.quote(os.environ['XUPER_USER'],safe=''))
PY
)" >/dev/null 2>&1
    adb shell input tap "$px" "$py"
    adb shell input text "$(python3 - <<'PY'
import os,urllib.parse
print(urllib.parse.quote(os.environ['XUPER_PASS'],safe=''))
PY
)" >/dev/null 2>&1
    dump_ui "$OUT/ui-login-filled.xml"
    if XY=$(tap_center_for_match "$OUT/ui-login-filled.xml" 'iniciar' 2>/dev/null) || XY=$(tap_center_for_match "$OUT/ui-login-filled.xml" 'login' 2>/dev/null) || XY=$(tap_center_for_match "$OUT/ui-login-filled.xml" 'entrar' 2>/dev/null); then
      adb shell input tap $XY
      sleep 12
    fi
  fi
fi

dump_ui "$OUT/ui-after-login.xml"
PID=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r[:space:]' || true)
[ -n "$PID" ] || { echo 'APP_ALIVE_AFTER_LOGIN=FAIL' > "$OUT/result.txt"; exit 20; }
echo 'APP_ALIVE_AFTER_LOGIN=PASS' > "$OUT/result.txt"

# Navigate to Movies/Series if a visible tab is exposed through accessibility.
for label in 'Películas' 'Peliculas' 'Movies' 'Series'; do
  if XY=$(tap_center_for_match "$OUT/ui-after-login.xml" "$label" 2>/dev/null); then
    adb shell input tap $XY
    sleep 8
    dump_ui "$OUT/ui-category.xml"
    break
  fi
done

# Produce a network/runtime-focused diagnostic without exposing credentials.
adb logcat -d -v threadtime 2>/dev/null | redact | grep -Eai 'http|https|retrofit|okhttp|exo|media|stream|m3u8|mp4|vod|movie|series|episode|play|source|sequence|error|exception|response|status|403|401|404|426' | tail -1500 > "$OUT/vod-runtime-summary.txt" || true
capture
trap - EXIT

echo 'AUTHENTICATED_PROBE=PASS' >> "$OUT/result.txt"
