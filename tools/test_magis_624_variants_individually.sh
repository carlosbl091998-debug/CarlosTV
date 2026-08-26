#!/usr/bin/env bash
set -u

PKG='com.msandroid.mobile'
APK='Magis-6.2.4.apk'
OUT='diagnostics-variants'
mkdir -p "$OUT"

APKSIGNER=$(find "$ANDROID_HOME/build-tools" -type f -name apksigner | sort -V | tail -1)
ZIPALIGN=$(find "$ANDROID_HOME/build-tools" -type f -name zipalign | sort -V | tail -1)

keytool -genkeypair -noprompt -keystore /tmp/magis-variants.jks -storepass android -keypass android -alias patch \
  -dname 'CN=Magis624VariantTest,O=LocalTest,C=MX' -keyalg RSA -keysize 2048 -validity 10000 >/dev/null 2>&1 || true

make_variant() {
  mode="$1"
  dir="$OUT/$mode"
  mkdir -p "$dir"
  python3 - "$APK" "$dir/unsigned.apk" "$mode" "$dir/replacements.txt" <<'PY'
import sys, zipfile, hashlib, zlib
src,out,mode,report=sys.argv[1:]
if mode == 'endpoint':
    repls=[(b'api/portalCore/box/update', b'api/portalCore/box/updatx')]
elif mode == 'flags':
    repls=[(b'forceUpdate', b'forceUpdatx'), (b'hasNewVersion', b'hasOldVersion')]
elif mode == 'combo':
    repls=[(b'api/portalCore/box/update', b'api/portalCore/box/updatx'),
           (b'forceUpdate', b'forceUpdatx'),
           (b'hasNewVersion', b'hasOldVersion'),
           (b'upgradeVerCode', b'upgradeVerCodx')]
else:
    raise SystemExit(mode)
with zipfile.ZipFile(src,'r') as zin:
    dex=bytearray(zin.read('classes.dex'))
    lines=[]
    for old,new in repls:
        n=dex.count(old)
        lines.append(f'{old.decode()} -> {new.decode()} count={n}')
        dex=dex.replace(old,new)
    dex[12:32]=hashlib.sha1(dex[32:]).digest()
    dex[8:12]=(zlib.adler32(dex[12:]) & 0xffffffff).to_bytes(4,'little')
    with zipfile.ZipFile(out,'w',allowZip64=True) as zout:
        for info in zin.infolist():
            name=info.filename
            upper=name.upper()
            if upper.startswith('META-INF/') and upper.endswith(('.RSA','.DSA','.EC','.SF','MANIFEST.MF')):
                continue
            data=bytes(dex) if name=='classes.dex' else zin.read(name)
            ni=zipfile.ZipInfo(name,date_time=info.date_time)
            ni.compress_type=info.compress_type
            ni.comment=info.comment; ni.extra=info.extra
            ni.internal_attr=info.internal_attr; ni.external_attr=info.external_attr
            ni.create_system=info.create_system
            zout.writestr(ni,data)
open(report,'w').write('\n'.join(lines)+'\n')
PY
  "$ZIPALIGN" -f -p 4 "$dir/unsigned.apk" "$dir/aligned.apk"
  "$APKSIGNER" sign --ks /tmp/magis-variants.jks --ks-key-alias patch --ks-pass pass:android --key-pass pass:android \
    --out "$dir/${mode}.apk" "$dir/aligned.apk"
  "$APKSIGNER" verify --verbose "$dir/${mode}.apk" > "$dir/signing.txt" 2>&1 || true
  sha256sum "$dir/${mode}.apk" > "$dir/sha256.txt"
}

for mode in endpoint flags combo; do make_variant "$mode"; done

adb wait-for-device
adb shell settings put system system_locales es-MX >/dev/null 2>&1 || true

permit() {
  adb shell pm grant "$PKG" android.permission.READ_MEDIA_AUDIO >/dev/null 2>&1 || true
  adb shell pm grant "$PKG" android.permission.READ_MEDIA_IMAGES >/dev/null 2>&1 || true
  adb shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true
  adb shell pm grant "$PKG" android.permission.CAMERA >/dev/null 2>&1 || true
}

dump_state() {
  tag="$1"
  timeout 10s adb shell uiautomator dump "/sdcard/${tag}.xml" >/dev/null 2>&1 || true
  timeout 10s adb pull "/sdcard/${tag}.xml" "$2/${tag}.xml" >/dev/null 2>&1 || true
  adb shell pidof "$PKG" 2>/dev/null | tr -d '\r' > "$2/${tag}.pid" || true
  adb shell dumpsys window windows 2>/dev/null | grep -E 'mCurrentFocus|mFocusedApp' | tail -4 > "$2/${tag}.focus.txt" || true
  timeout 10s adb exec-out screencap -p > "$2/${tag}.png" || true
}

gate_present() {
  f="$1"
  [ -s "$f" ] || return 1
  grep -Eiq 'Actualizaci[oó]n de versi[oó]n|Version Upgrade|V6\.5\.5|Versi[oó]n actual:6\.2\.4|Current version:6\.2\.4|gaeg\.xvmobdes\.com/download' "$f"
}

test_variant() {
  mode="$1"
  dir="$OUT/$mode"
  apk="$dir/${mode}.apk"
  : > "$dir/result.txt"
  adb uninstall "$PKG" >/dev/null 2>&1 || true
  adb logcat -c || true
  if ! adb install -g "$apk" > "$dir/install.txt" 2>&1; then
    echo 'INSTALL=FAIL' | tee -a "$dir/result.txt"
    return
  fi
  echo 'INSTALL=PASS' | tee -a "$dir/result.txt"
  permit
  adb shell am force-stop "$PKG" >/dev/null 2>&1 || true
  timeout 20s adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > "$dir/launch.txt" 2>&1 || true
  sleep 15
  dump_state t15 "$dir"
  p15=$(cat "$dir/t15.pid" 2>/dev/null | tr -d '[:space:]')
  if [ -n "$p15" ]; then echo 'ALIVE15=PASS' | tee -a "$dir/result.txt"; else echo 'ALIVE15=FAIL' | tee -a "$dir/result.txt"; fi
  if gate_present "$dir/t15.xml"; then echo 'GATE15=PRESENT' | tee -a "$dir/result.txt"; else echo 'GATE15=ABSENT' | tee -a "$dir/result.txt"; fi
  sleep 30
  dump_state t45 "$dir"
  p45=$(cat "$dir/t45.pid" 2>/dev/null | tr -d '[:space:]')
  if [ -n "$p45" ]; then echo 'ALIVE45=PASS' | tee -a "$dir/result.txt"; else echo 'ALIVE45=FAIL' | tee -a "$dir/result.txt"; fi
  if gate_present "$dir/t45.xml"; then echo 'GATE45=PRESENT' | tee -a "$dir/result.txt"; else echo 'GATE45=ABSENT' | tee -a "$dir/result.txt"; fi
  adb logcat -d -v threadtime > "$dir/logcat.txt" || true
  grep -E 'FATAL EXCEPTION|AndroidRuntime|Process: com\.msandroid\.mobile|SecurityException|UnsatisfiedLinkError|VerifyError' "$dir/logcat.txt" | tail -120 > "$dir/crash-summary.txt" || true
  if [ -n "$p15" ] && [ -n "$p45" ] && ! gate_present "$dir/t15.xml" && ! gate_present "$dir/t45.xml"; then
    echo 'FINAL=PASS_RUNTIME' | tee -a "$dir/result.txt"
  else
    echo 'FINAL=FAIL_RUNTIME_OR_GATE' | tee -a "$dir/result.txt"
  fi
}

for mode in endpoint flags combo; do
  echo "===== TEST $mode ====="
  test_variant "$mode"
done

{
  for mode in endpoint flags combo; do
    echo "===== $mode ====="
    cat "$OUT/$mode/result.txt" 2>/dev/null || true
    echo
  done
} | tee "$OUT/summary.txt"

exit 0
