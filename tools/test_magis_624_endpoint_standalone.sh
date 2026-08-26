#!/usr/bin/env bash
set -euo pipefail
PKG='com.msandroid.mobile'
APK='Magis-6.2.4.apk'
OUT='diagnostics-endpoint-standalone'
mkdir -p "$OUT"

AAPT=$(find "$ANDROID_HOME/build-tools" -type f -name aapt | sort -V | tail -1)
APKSIGNER=$(find "$ANDROID_HOME/build-tools" -type f -name apksigner | sort -V | tail -1)
ZIPALIGN=$(find "$ANDROID_HOME/build-tools" -type f -name zipalign | sort -V | tail -1)

python3 - "$APK" "$OUT/endpoint-unsigned.apk" <<'PY'
import sys,zipfile,hashlib,zlib
src,out=sys.argv[1:]
old=b'api/portalCore/box/update'; new=b'api/portalCore/box/updatx'
with zipfile.ZipFile(src) as zin:
    dex=bytearray(zin.read('classes.dex'))
    n=dex.count(old)
    print('endpoint_matches=',n)
    if n != 1: raise SystemExit(20)
    dex=dex.replace(old,new)
    dex[12:32]=hashlib.sha1(dex[32:]).digest()
    dex[8:12]=(zlib.adler32(dex[12:]) & 0xffffffff).to_bytes(4,'little')
    with zipfile.ZipFile(out,'w',allowZip64=True) as zout:
        for info in zin.infolist():
            name=info.filename
            if name.upper().startswith('META-INF/') and name.upper().endswith(('.RSA','.DSA','.EC','.SF','MANIFEST.MF')):
                continue
            data=bytes(dex) if name=='classes.dex' else zin.read(name)
            ni=zipfile.ZipInfo(name,date_time=info.date_time)
            ni.compress_type=info.compress_type; ni.comment=info.comment; ni.extra=info.extra
            ni.internal_attr=info.internal_attr; ni.external_attr=info.external_attr; ni.create_system=info.create_system
            zout.writestr(ni,data)
PY

"$ZIPALIGN" -f -p 4 "$OUT/endpoint-unsigned.apk" "$OUT/endpoint-aligned.apk"
keytool -genkeypair -noprompt -keystore /tmp/endpoint.jks -storepass android -keypass android -alias endpoint \
  -dname 'CN=Magis624EndpointTest,O=LocalTest,C=MX' -keyalg RSA -keysize 2048 -validity 10000 >/dev/null 2>&1
"$APKSIGNER" sign --ks /tmp/endpoint.jks --ks-key-alias endpoint --ks-pass pass:android --key-pass pass:android \
  --out "$OUT/Magis-6.2.4-ENDPOINT-TEST.apk" "$OUT/endpoint-aligned.apk"
"$APKSIGNER" verify --verbose --print-certs "$OUT/Magis-6.2.4-ENDPOINT-TEST.apk" > "$OUT/signing.txt"
"$AAPT" dump badging "$OUT/Magis-6.2.4-ENDPOINT-TEST.apk" > "$OUT/badging.txt"
sha256sum "$OUT/Magis-6.2.4-ENDPOINT-TEST.apk" > "$OUT/sha256.txt"

grant_perms() {
 adb shell pm grant "$PKG" android.permission.READ_MEDIA_AUDIO >/dev/null 2>&1 || true
 adb shell pm grant "$PKG" android.permission.READ_MEDIA_IMAGES >/dev/null 2>&1 || true
 adb shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true
 adb shell pm grant "$PKG" android.permission.CAMERA >/dev/null 2>&1 || true
 adb shell pm grant "$PKG" android.permission.READ_EXTERNAL_STORAGE >/dev/null 2>&1 || true
}
dump() {
 local tag="$1"
 adb shell pidof "$PKG" 2>/dev/null | tr -d '\r' > "$OUT/${tag}.pid" || true
 timeout 8s adb shell uiautomator dump "/sdcard/${tag}.xml" >/dev/null 2>&1 || true
 timeout 8s adb pull "/sdcard/${tag}.xml" "$OUT/${tag}.xml" >/dev/null 2>&1 || true
 adb exec-out screencap -p > "$OUT/${tag}.png" || true
}

adb uninstall "$PKG" >/dev/null 2>&1 || true
adb install -g "$OUT/Magis-6.2.4-ENDPOINT-TEST.apk" | tee "$OUT/install.txt"
grant_perms
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
sleep 20
dump t20
sleep 40
dump t60
P20=$(cat "$OUT/t20.pid" | tr -d '[:space:]' || true)
P60=$(cat "$OUT/t60.pid" | tr -d '[:space:]' || true)
echo "pid20=${P20:-DEAD}" | tee "$OUT/result.txt"
echo "pid60=${P60:-DEAD}" | tee -a "$OUT/result.txt"
if [[ -n "$P20" && -n "$P60" ]]; then
  echo 'standalone=RUNTIME_STABLE' | tee -a "$OUT/result.txt"
  cp "$OUT/Magis-6.2.4-ENDPOINT-TEST.apk" "$OUT/Magis-6.2.4-ENDPOINT-STANDALONE-PASSED.apk"
else
  echo 'standalone=RUNTIME_DEAD' | tee -a "$OUT/result.txt"
fi
adb logcat -d -v threadtime | grep -Ei 'com\.msandroid\.mobile|AndroidRuntime|FATAL EXCEPTION|System\.exit|EXIT_SELF|SecNeo|Bangcle|ijiami' | tail -1200 > "$OUT/logcat.txt" || true
