#!/usr/bin/env bash
set -u
PKG='com.msandroid.mobile'
APK='Magis-6.2.4.apk'
OUT='diagnostics-resign-control'
mkdir -p "$OUT/original" "$OUT/resigned"
APKSIGNER=$(find "$ANDROID_HOME/build-tools" -type f -name apksigner | sort -V | tail -1)
ZIPALIGN=$(find "$ANDROID_HOME/build-tools" -type f -name zipalign | sort -V | tail -1)
keytool -genkeypair -noprompt -keystore /tmp/resign-control.jks -storepass android -keypass android -alias patch -dname 'CN=Magis624Control,O=LocalTest,C=MX' -keyalg RSA -keysize 2048 -validity 10000 >/dev/null 2>&1 || true
cp "$APK" "$OUT/original/original.apk"
python3 - "$APK" "$OUT/resigned/unsigned.apk" <<'PY'
import sys, zipfile
src,out=sys.argv[1:]
with zipfile.ZipFile(src,'r') as zin, zipfile.ZipFile(out,'w',allowZip64=True) as zout:
    for info in zin.infolist():
        upper=info.filename.upper()
        if upper.startswith('META-INF/') and upper.endswith(('.RSA','.DSA','.EC','.SF','MANIFEST.MF')):
            continue
        data=zin.read(info.filename)
        ni=zipfile.ZipInfo(info.filename,date_time=info.date_time)
        ni.compress_type=info.compress_type
        ni.comment=info.comment; ni.extra=info.extra
        ni.internal_attr=info.internal_attr; ni.external_attr=info.external_attr
        ni.create_system=info.create_system
        zout.writestr(ni,data)
PY
"$ZIPALIGN" -f -p 4 "$OUT/resigned/unsigned.apk" "$OUT/resigned/aligned.apk"
"$APKSIGNER" sign --ks /tmp/resign-control.jks --ks-key-alias patch --ks-pass pass:android --key-pass pass:android --out "$OUT/resigned/resigned.apk" "$OUT/resigned/aligned.apk"
sha256sum "$OUT/original/original.apk" "$OUT/resigned/resigned.apk" > "$OUT/sha256.txt"

permit(){
  adb shell pm grant "$PKG" android.permission.READ_MEDIA_AUDIO >/dev/null 2>&1 || true
  adb shell pm grant "$PKG" android.permission.READ_MEDIA_IMAGES >/dev/null 2>&1 || true
  adb shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true
  adb shell pm grant "$PKG" android.permission.CAMERA >/dev/null 2>&1 || true
}

test_one(){
  name="$1"; apk="$2"; dir="$OUT/$name"; mkdir -p "$dir"
  adb uninstall "$PKG" >/dev/null 2>&1 || true
  adb logcat -c || true
  if ! adb install -g "$apk" > "$dir/install.txt" 2>&1; then echo 'INSTALL=FAIL' | tee "$dir/result.txt"; return; fi
  echo 'INSTALL=PASS' | tee "$dir/result.txt"
  permit
  adb shell am force-stop "$PKG" >/dev/null 2>&1 || true
  timeout 20s adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > "$dir/launch.txt" 2>&1 || true
  sleep 8
  pid8=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r[:space:]')
  [ -n "$pid8" ] && echo 'ALIVE8=PASS' | tee -a "$dir/result.txt" || echo 'ALIVE8=FAIL' | tee -a "$dir/result.txt"
  sleep 12
  pid20=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r[:space:]')
  [ -n "$pid20" ] && echo 'ALIVE20=PASS' | tee -a "$dir/result.txt" || echo 'ALIVE20=FAIL' | tee -a "$dir/result.txt"
  adb logcat -d -v threadtime > "$dir/logcat.txt" || true
  grep -E 'Fatal signal|SIGSEGV|Abort message|com\.msandroid\.mobile|play_station|signature|verify|dexjni|DexHelper' "$dir/logcat.txt" | tail -200 > "$dir/native-summary.txt" || true
  timeout 10s adb exec-out screencap -p > "$dir/final.png" || true
}

adb wait-for-device
test_one original "$OUT/original/original.apk"
test_one resigned "$OUT/resigned/resigned.apk"
{
  echo '=== ORIGINAL ==='; cat "$OUT/original/result.txt" 2>/dev/null || true
  echo '=== RESIGNED ==='; cat "$OUT/resigned/result.txt" 2>/dev/null || true
} | tee "$OUT/summary.txt"
exit 0
