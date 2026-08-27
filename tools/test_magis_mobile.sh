#!/usr/bin/env bash
set -euo pipefail

PKG='com.msandroid.mobile'
ACTIVITY='com.mobile.brasiltv.activity.SplashAty'
COMPONENT="$PKG/$ACTIVITY"
OUT='diagnostics'
mkdir -p "$OUT"

run_timeout() {
  local secs="$1"; shift
  timeout "$secs" "$@"
}

dump_stage() {
  local tag="$1"
  local remote="/sdcard/magis-${tag}.xml"
  run_timeout 10s adb shell uiautomator dump "$remote" >/dev/null 2>&1 || true
  run_timeout 10s adb pull "$remote" "$OUT/ui-${tag}.xml" >/dev/null 2>&1 || true
  run_timeout 10s adb exec-out screencap -p > "$OUT/screen-${tag}.png" || true
  adb shell dumpsys window windows | grep -E 'mCurrentFocus|mFocusedApp' | head -6 > "$OUT/focus-${tag}.txt" || true
}

echo "Installing candidate with runtime permissions granted..."
run_timeout 45s adb install -r -g magis-current.apk | tee "$OUT/install.txt"

# Explicit grants are harmless if already granted and prevent first-run system dialogs
# from hiding the application's own update/login UI during the smoke test.
for perm in \
  android.permission.POST_NOTIFICATIONS \
  android.permission.READ_MEDIA_AUDIO \
  android.permission.READ_MEDIA_IMAGES \
  android.permission.CAMERA; do
  adb shell pm grant "$PKG" "$perm" >/dev/null 2>&1 || true
done

adb shell am force-stop "$PKG" || true
adb logcat -c || true

echo "component=$COMPONENT" | tee "$OUT/runtime.txt"
run_timeout 20s adb shell am start -W -n "$COMPONENT" | tee "$OUT/start.txt" || true

sleep 15
PID15=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true)
echo "pid_15s=${PID15:-DEAD}" | tee -a "$OUT/runtime.txt"
dump_stage 15

sleep 30
PID45=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true)
echo "pid_45s=${PID45:-DEAD}" | tee -a "$OUT/runtime.txt"
dump_stage 45

adb shell dumpsys package "$PKG" | grep -E 'versionName=|versionCode=' | head -10 > "$OUT/installed-version.txt" || true
adb logcat -d -v threadtime | grep -Ei 'com\.msandroid\.mobile|FATAL EXCEPTION|AndroidRuntime|SIGKILL|EXIT_SELF|UnsatisfiedLinkError|upgrade|update|version' | tail -1000 > "$OUT/logcat-relevant.txt" || true

python3 - <<'PY'
from pathlib import Path
import re, html
out=[]
all_text=[]
for tag in ('15','45'):
    fn=f'diagnostics/ui-{tag}.xml'
    p=Path(fn)
    t=p.read_text(errors='ignore') if p.exists() else ''
    vals=[html.unescape(v) for v in re.findall(r'text="([^"]*)"', t)]
    desc=[html.unescape(v) for v in re.findall(r'content-desc="([^"]*)"', t)]
    out.append(fn+':')
    out.extend('  text: '+v for v in vals if v.strip())
    out.extend('  desc: '+v for v in desc if v.strip())
    all_text.extend(v for v in vals+desc if v.strip())
Path('diagnostics/ui-text.txt').write_text('\n'.join(out), encoding='utf-8')
low='\n'.join(all_text).lower()
keys=('update','upgrade','actualiz','versión','version','discontinued','out of service','atualiz')
hits=sorted({line for line in all_text if any(k in line.lower() for k in keys)})
Path('diagnostics/update-text-hits.txt').write_text('\n'.join(hits), encoding='utf-8')
print('UPDATE_TEXT_HITS=', len(hits))
for h in hits: print('  ',h)
PY
cat "$OUT/ui-text.txt" || true

echo "=== focus at 45s ==="
cat "$OUT/focus-45.txt" || true
echo "=== process status ==="
cat "$OUT/runtime.txt"

if [[ -z "$PID15" || -z "$PID45" ]]; then
  echo 'MAGIS_RUNTIME_FAIL: process did not remain alive' >&2
  exit 20
fi

echo 'MAGIS_RUNTIME_ALIVE_OK'
