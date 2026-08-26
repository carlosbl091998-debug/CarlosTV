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

echo "Installing candidate..."
run_timeout 45s adb install -r magis-current.apk | tee "$OUT/install.txt"
adb shell am force-stop "$PKG" || true
adb logcat -c || true

echo "component=$COMPONENT" | tee "$OUT/runtime.txt"
run_timeout 20s adb shell am start -W -n "$COMPONENT" | tee "$OUT/start.txt" || true

sleep 10
PID10=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true)
echo "pid_10s=${PID10:-DEAD}" | tee -a "$OUT/runtime.txt"
run_timeout 10s adb shell uiautomator dump /sdcard/magis-10.xml >/dev/null 2>&1 || true
run_timeout 10s adb pull /sdcard/magis-10.xml "$OUT/ui-10.xml" >/dev/null 2>&1 || true
run_timeout 10s adb exec-out screencap -p > "$OUT/screen-10.png" || true

sleep 20
PID30=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true)
echo "pid_30s=${PID30:-DEAD}" | tee -a "$OUT/runtime.txt"
run_timeout 10s adb shell uiautomator dump /sdcard/magis-30.xml >/dev/null 2>&1 || true
run_timeout 10s adb pull /sdcard/magis-30.xml "$OUT/ui-30.xml" >/dev/null 2>&1 || true
run_timeout 10s adb exec-out screencap -p > "$OUT/screen-30.png" || true

adb shell dumpsys package "$PKG" | grep -E 'versionName=|versionCode=' | head -10 > "$OUT/installed-version.txt" || true
adb logcat -d -v threadtime | grep -Ei 'com\.msandroid\.mobile|FATAL EXCEPTION|AndroidRuntime|SIGKILL|EXIT_SELF|UnsatisfiedLinkError' | tail -700 > "$OUT/logcat-relevant.txt" || true

python3 - <<'PY'
from pathlib import Path
import re
out=[]
for fn in ('diagnostics/ui-10.xml','diagnostics/ui-30.xml'):
    p=Path(fn)
    t=p.read_text(errors='ignore') if p.exists() else ''
    vals=re.findall(r'text="([^"]*)"', t)
    desc=re.findall(r'content-desc="([^"]*)"', t)
    out.append(fn+':')
    out.extend('  text: '+v for v in vals if v.strip())
    out.extend('  desc: '+v for v in desc if v.strip())
Path('diagnostics/ui-text.txt').write_text('\n'.join(out), encoding='utf-8')
PY
cat "$OUT/ui-text.txt" || true

echo "=== process status ==="
cat "$OUT/runtime.txt"

if [[ -z "$PID10" || -z "$PID30" ]]; then
  echo 'MAGIS_RUNTIME_FAIL: process did not remain alive' >&2
  exit 20
fi

echo 'MAGIS_RUNTIME_ALIVE_OK'
