#!/usr/bin/env bash
set -euo pipefail

PKG='com.msandroid.mobile'
MAIN='com.mobile.brasiltv.activity.MainAty'
SRC='Magis-6.2.4.apk'
OUT='diagnostics-manifest-version'
WORK='/tmp/magis-manifest-work'
VERSION_CODE='900000'
mkdir -p "$OUT" "$WORK"

APKSIGNER=$(find "$ANDROID_HOME/build-tools" -type f -name apksigner | sort -V | tail -1)
ZIPALIGN=$(find "$ANDROID_HOME/build-tools" -type f -name zipalign | sort -V | tail -1)
AAPT=$(find "$ANDROID_HOME/build-tools" -type f -name aapt | sort -V | tail -1)

# Decode resources but never decompile/rebuild classes.dex. This candidate changes only manifest metadata.
apktool d -f -s "$SRC" -o "$WORK/decoded" > "$OUT/apktool-decode.txt" 2>&1
cp "$WORK/decoded/AndroidManifest.xml" "$OUT/AndroidManifest.before.xml"
python3 - "$WORK/decoded/AndroidManifest.xml" "$VERSION_CODE" <<'PY'
import re,sys
p,v=sys.argv[1:]
s=open(p,encoding='utf-8').read()
s2,n=re.subn(r'android:versionCode="[0-9]+"',f'android:versionCode="{v}"',s,count=1)
if n != 1:
    raise SystemExit(f'versionCode replacements={n}')
open(p,'w',encoding='utf-8').write(s2)
PY
cp "$WORK/decoded/AndroidManifest.xml" "$OUT/AndroidManifest.after.xml"
apktool b "$WORK/decoded" -o "$WORK/unsigned.apk" > "$OUT/apktool-build.txt" 2>&1

# Ensure the protected DEX payload is byte-identical to the official APK.
unzip -p "$SRC" classes.dex | sha256sum | awk '{print $1}' > "$OUT/classes-source.sha256"
unzip -p "$WORK/unsigned.apk" classes.dex | sha256sum | awk '{print $1}' > "$OUT/classes-candidate.sha256"
diff -u "$OUT/classes-source.sha256" "$OUT/classes-candidate.sha256" > "$OUT/classes-diff.txt" || {
  echo 'DEX_IDENTICAL=FAIL' | tee "$OUT/result.txt"
  exit 11
}
echo 'DEX_IDENTICAL=PASS' | tee "$OUT/result.txt"

keytool -genkeypair -noprompt -keystore /tmp/magis-manifest.jks -storepass android -keypass android -alias patch -dname 'CN=MagisManifestCandidate,O=LocalTest,C=MX' -keyalg RSA -keysize 2048 -validity 10000 >/dev/null 2>&1 || true
"$ZIPALIGN" -f -p 4 "$WORK/unsigned.apk" "$WORK/aligned.apk"
"$APKSIGNER" sign --ks /tmp/magis-manifest.jks --ks-key-alias patch --ks-pass pass:android --key-pass pass:android --out "$OUT/Magis-6.2.4-ManifestVersion900000-Tested.apk" "$WORK/aligned.apk"
"$APKSIGNER" verify --verbose "$OUT/Magis-6.2.4-ManifestVersion900000-Tested.apk" > "$OUT/signature-verify.txt"
"$AAPT" dump badging "$OUT/Magis-6.2.4-ManifestVersion900000-Tested.apk" > "$OUT/badging.txt"
grep -q "versionCode='900000'" "$OUT/badging.txt"
sha256sum "$OUT/Magis-6.2.4-ManifestVersion900000-Tested.apk" > "$OUT/candidate.sha256"

adb wait-for-device
adb uninstall "$PKG" >/dev/null 2>&1 || true
adb logcat -c || true
if ! adb install -g "$OUT/Magis-6.2.4-ManifestVersion900000-Tested.apk" > "$OUT/install.txt" 2>&1; then
  echo 'INSTALL=FAIL' | tee -a "$OUT/result.txt"
  exit 12
fi
echo 'INSTALL=PASS' | tee -a "$OUT/result.txt"

# Best-effort grants so the test exercises app startup rather than stopping at Android permission UI.
for perm in android.permission.READ_MEDIA_AUDIO android.permission.READ_MEDIA_IMAGES android.permission.POST_NOTIFICATIONS android.permission.CAMERA; do
  adb shell pm grant "$PKG" "$perm" >/dev/null 2>&1 || true
done
adb shell appops set "$PKG" MANAGE_EXTERNAL_STORAGE allow >/dev/null 2>&1 || true
adb shell am force-stop "$PKG" >/dev/null 2>&1 || true
timeout 20s adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > "$OUT/launch.txt" 2>&1 || true

check_point() {
  local sec="$1"
  local pid top xml
  pid=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r[:space:]' || true)
  adb shell dumpsys activity activities > "$OUT/activities-${sec}s.txt" || true
  top=$(grep -E 'topResumedActivity|mResumedActivity' "$OUT/activities-${sec}s.txt" | head -5 || true)
  timeout 10s adb shell uiautomator dump /sdcard/window.xml >/dev/null 2>&1 || true
  adb pull /sdcard/window.xml "$OUT/window-${sec}s.xml" >/dev/null 2>&1 || true
  timeout 10s adb exec-out screencap -p > "$OUT/screen-${sec}s.png" || true
  if [ -n "$pid" ]; then echo "ALIVE_${sec}=PASS" | tee -a "$OUT/result.txt"; else echo "ALIVE_${sec}=FAIL" | tee -a "$OUT/result.txt"; return 1; fi
  if printf '%s' "$top" | grep -q 'MainAty'; then echo "MAINATY_${sec}=PASS" | tee -a "$OUT/result.txt"; else echo "MAINATY_${sec}=FAIL" | tee -a "$OUT/result.txt"; return 1; fi
  if [ -s "$OUT/window-${sec}s.xml" ] && grep -Eiq 'actualiz|update|upgrade|new version|nova vers|atualiz|versi[oó]n disponible|descargar.*versi' "$OUT/window-${sec}s.xml"; then
    echo "UPDATE_GATE_${sec}=FAIL" | tee -a "$OUT/result.txt"
    grep -Eio '.{0,100}(actualiz|update|upgrade|new version|nova vers|atualiz).{0,160}' "$OUT/window-${sec}s.xml" | head -20 > "$OUT/update-hits-${sec}s.txt" || true
    return 1
  else
    echo "UPDATE_GATE_${sec}=PASS" | tee -a "$OUT/result.txt"
  fi
}

sleep 20
check_point 20
sleep 40
check_point 60
adb logcat -d -v threadtime > "$OUT/logcat.txt" || true
grep -E 'Fatal signal|SIGSEGV|FATAL EXCEPTION|AndroidRuntime|com\.msandroid\.mobile|play_station|DexHelper|dexjni' "$OUT/logcat.txt" | tail -300 > "$OUT/runtime-summary.txt" || true

# Hard success marker used by the automation: every required criterion must pass.
for marker in DEX_IDENTICAL INSTALL ALIVE_20 MAINATY_20 UPDATE_GATE_20 ALIVE_60 MAINATY_60 UPDATE_GATE_60; do
  grep -q "^${marker}=PASS$" "$OUT/result.txt" || { echo 'VALIDATED=FAIL' | tee -a "$OUT/result.txt"; exit 20; }
done
echo 'VALIDATED=PASS' | tee -a "$OUT/result.txt"
