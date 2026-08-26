#!/usr/bin/env bash
set -euo pipefail

# MAGIS 6.2.4 ONLY. This test never updates to 6.5.5.
PKG='com.msandroid.mobile'
OUT='diagnostics-update'
APK624='Magis-6.2.4.apk'
EXPECTED_SHA='04bda60a0ebb003d1442483401978f39b601d989004d7b5e9c1f213a127d8835'
EXPECTED_CERT='d30dc60fd8625d49fa4e82eb442c9307743f9621004b94e229dcc01f6a9035ff'
mkdir -p "$OUT/static-tests"

AAPT=$(find "$ANDROID_HOME/build-tools" -type f -name aapt | sort -V | tail -1)
APKSIGNER=$(find "$ANDROID_HOME/build-tools" -type f -name apksigner | sort -V | tail -1)
ZIPALIGN=$(find "$ANDROID_HOME/build-tools" -type f -name zipalign | sort -V | tail -1)

# Hard validation of the exact official 6.2.4 that previously passed Android 16.
test -s "$APK624"
echo "$EXPECTED_SHA  $APK624" | sha256sum -c -
unzip -t "$APK624" >/dev/null
"$AAPT" dump badging "$APK624" | tee "$OUT/base-badging.txt"
grep -q "package: name='$PKG' versionCode='60204' versionName='6.2.4'" "$OUT/base-badging.txt"
"$APKSIGNER" verify --verbose --print-certs "$APK624" | tee "$OUT/base-signing.txt"
CERT=$($APKSIGNER verify --print-certs "$APK624" 2>/dev/null | sed -n 's/.*certificate SHA-256 digest: //p' | head -1 | tr -d ':[:space:]' | tr '[:upper:]' '[:lower:]')
[[ "$CERT" == "$EXPECTED_CERT" ]]
sha256sum "$APK624" | tee "$OUT/base-sha256.txt"

# A local signer is used only for the standalone-install control. The primary
# bind-mount candidates preserve the original META-INF certificate files.
keytool -genkeypair -noprompt -keystore /tmp/magis-patch.jks -storepass android -keypass android -alias patch \
  -dname 'CN=Magis624UpdateGateTest,O=LocalTest,C=MX' -keyalg RSA -keysize 2048 -validity 10000 >/dev/null 2>&1

make_variant() {
  local mode="$1"
  local dir="$OUT/static-tests/$mode"
  mkdir -p "$dir"
  python3 - "$APK624" "$dir/mount.apk" "$dir/unsigned.apk" "$mode" "$dir/replacements.txt" <<'PY'
import sys, zipfile, hashlib, zlib
src,mount_out,unsigned_out,mode,report=sys.argv[1:]
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
    raise SystemExit('unknown mode')

with zipfile.ZipFile(src,'r') as zin:
    dex=bytearray(zin.read('classes.dex'))
    lines=[]
    for old,new in repls:
        if len(old) != len(new): raise SystemExit('length mismatch')
        n=dex.count(old)
        lines.append(f'{old.decode()} -> {new.decode()} count={n}')
        if n: dex=dex.replace(old,new)
    dex[12:32]=hashlib.sha1(dex[32:]).digest()
    dex[8:12]=(zlib.adler32(dex[12:]) & 0xffffffff).to_bytes(4,'little')
    entries=zin.infolist()
    def write_apk(path, strip_signatures):
        with zipfile.ZipFile(path,'w',allowZip64=True) as zout:
            for info in entries:
                name=info.filename
                upper=name.upper()
                if strip_signatures and upper.startswith('META-INF/') and upper.endswith(('.RSA','.DSA','.EC','.SF','MANIFEST.MF')):
                    continue
                data=bytes(dex) if name=='classes.dex' else zin.read(name)
                ni=zipfile.ZipInfo(name,date_time=info.date_time)
                ni.compress_type=info.compress_type
                ni.comment=info.comment; ni.extra=info.extra
                ni.internal_attr=info.internal_attr; ni.external_attr=info.external_attr
                ni.create_system=info.create_system
                zout.writestr(ni,data)
    write_apk(mount_out, False)
    write_apk(unsigned_out, True)
open(report,'w').write('\n'.join(lines)+'\n')
PY
  cat "$dir/replacements.txt"
  unzip -t "$dir/mount.apk" >/dev/null
  "$ZIPALIGN" -f -p 4 "$dir/unsigned.apk" "$dir/aligned.apk"
  "$APKSIGNER" sign --ks /tmp/magis-patch.jks --ks-key-alias patch --ks-pass pass:android --key-pass pass:android \
    --out "$dir/standalone.apk" "$dir/aligned.apk"
  "$APKSIGNER" verify --verbose --print-certs "$dir/standalone.apk" > "$dir/standalone-signing.txt"
  sha256sum "$dir/mount.apk" "$dir/standalone.apk" > "$dir/sha256.txt"
}

make_variant endpoint
make_variant flags
make_variant combo

adb root || true
adb wait-for-device
adb shell setenforce 0 >/dev/null 2>&1 || true
adb emu geo fix -99.1332 19.4326 >/dev/null 2>&1 || true
adb shell settings put system system_locales es-MX >/dev/null 2>&1 || true

launch_app() {
  adb shell am force-stop "$PKG" >/dev/null 2>&1 || true
  timeout 20s adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
}

dump_state() {
  local tag="$1"
  timeout 10s adb shell uiautomator dump "/sdcard/${tag}.xml" >/dev/null 2>&1 || true
  timeout 10s adb pull "/sdcard/${tag}.xml" "$OUT/${tag}.xml" >/dev/null 2>&1 || true
  timeout 10s adb exec-out screencap -p > "$OUT/${tag}.png" || true
  adb shell pidof "$PKG" 2>/dev/null | tr -d '\r' > "$OUT/${tag}.pid" || true
}

gate_present() {
  local f="$1"
  [[ -s "$f" ]] || return 1
  grep -Eiq 'Actualizaci[oó]n de versi[oó]n|Version Upgrade|V6\.5\.5|Versi[oó]n actual:6\.2\.4|Current version:6\.2\.4|gaeg\.xvmobdes\.com/download' "$f"
}

# Control: prove that the unmodified official 6.2.4 currently reproduces the gate.
adb install -r -g "$APK624" | tee "$OUT/install-official.txt"
adb shell pm clear "$PKG" >/dev/null 2>&1 || true
launch_app
sleep 20
dump_state baseline20
sleep 20
dump_state baseline40
BASE=$(adb shell pm path "$PKG" | sed -n 's/^package://p' | head -1 | tr -d '\r')
echo "base_path=$BASE" | tee "$OUT/base-path.txt"
[[ -n "$BASE" ]]
BASE_GATE=0
if gate_present "$OUT/baseline20.xml" || gate_present "$OUT/baseline40.xml"; then BASE_GATE=1; fi
echo "baseline_gate=$BASE_GATE" | tee "$OUT/baseline-result.txt"
if [[ "$BASE_GATE" != 1 ]]; then
  echo 'BASELINE_DID_NOT_REPRODUCE_UPDATE_GATE' | tee "$OUT/result.txt"
  adb logcat -d -v threadtime > "$OUT/baseline-logcat.txt" || true
  exit 73
fi

bind_test() {
  local mode="$1" dir="$OUT/static-tests/$mode" remote="/data/local/tmp/magis-${mode}.apk"
  adb shell am force-stop "$PKG" >/dev/null 2>&1 || true
  adb shell "umount '$BASE' 2>/dev/null || true"
  adb push "$dir/mount.apk" "$remote" >/dev/null
  adb shell "mount --bind '$remote' '$BASE'" || return 2
  adb shell pm clear "$PKG" >/dev/null 2>&1 || true
  launch_app
  sleep 20
  dump_state "static-tests/${mode}/bind20"
  local p20; p20=$(cat "$OUT/static-tests/${mode}/bind20.pid" 2>/dev/null | tr -d '[:space:]' || true)
  if [[ -z "$p20" ]] || gate_present "$OUT/static-tests/${mode}/bind20.xml"; then
    echo 'bind=FAIL20' | tee "$dir/bind-result.txt"
    return 1
  fi
  sleep 40
  dump_state "static-tests/${mode}/bind60"
  local p60; p60=$(cat "$OUT/static-tests/${mode}/bind60.pid" 2>/dev/null | tr -d '[:space:]' || true)
  if [[ -z "$p60" ]] || gate_present "$OUT/static-tests/${mode}/bind60.xml"; then
    echo 'bind=FAIL60' | tee "$dir/bind-result.txt"
    return 1
  fi
  echo 'bind=PASS' | tee "$dir/bind-result.txt"
  return 0
}

WINNER=''
for mode in endpoint flags combo; do
  echo "=== BIND TEST $mode ===" | tee -a "$OUT/actions.txt"
  if bind_test "$mode"; then WINNER="$mode"; break; fi
  adb shell am force-stop "$PKG" >/dev/null 2>&1 || true
  adb shell "umount '$BASE' 2>/dev/null || true"
done

if [[ -z "$WINNER" ]]; then
  adb shell am force-stop "$PKG" >/dev/null 2>&1 || true
  adb shell "umount '$BASE' 2>/dev/null || true"
  echo 'STATIC_VARIANTS_FAILED' | tee "$OUT/result.txt"
  adb logcat -d -v threadtime > "$OUT/static-logcat.txt" || true
  exit 74
fi

echo "winner=$WINNER" | tee "$OUT/winner.txt"
W="$OUT/static-tests/$WINNER"
cp "$W/mount.apk" "$OUT/Magis-6.2.4-SIN-ACTUALIZACION-MOUNT-TESTED.apk"

# Standalone control: this is the only file that may be delivered as an APK.
adb shell am force-stop "$PKG" >/dev/null 2>&1 || true
adb shell "umount '$BASE' 2>/dev/null || true"
adb uninstall "$PKG" >/dev/null 2>&1 || true
if adb install -g "$W/standalone.apk" > "$OUT/standalone-install.txt" 2>&1; then
  adb shell pm clear "$PKG" >/dev/null 2>&1 || true
  launch_app
  sleep 20
  dump_state standalone20
  sleep 40
  dump_state standalone60
  P20=$(cat "$OUT/standalone20.pid" 2>/dev/null | tr -d '[:space:]' || true)
  P60=$(cat "$OUT/standalone60.pid" 2>/dev/null | tr -d '[:space:]' || true)
  if [[ -n "$P20" && -n "$P60" ]] && ! gate_present "$OUT/standalone20.xml" && ! gate_present "$OUT/standalone60.xml"; then
    cp "$W/standalone.apk" "$OUT/Magis-6.2.4-SIN-ACTUALIZACION-STANDALONE-TESTED.apk"
    sha256sum "$OUT/Magis-6.2.4-SIN-ACTUALIZACION-STANDALONE-TESTED.apk" > "$OUT/standalone-tested.sha256"
    echo 'standalone=PASS' | tee "$OUT/standalone-result.txt"
  else
    echo 'standalone=FAIL_RUNTIME_OR_GATE' | tee "$OUT/standalone-result.txt"
  fi
else
  echo 'standalone=FAIL_INSTALL' | tee "$OUT/standalone-result.txt"
fi

# Preserve a usable Magisk form whenever bind-mount passed, even if the
# standalone re-signed APK is rejected by SecNeo.
MOD="$OUT/magisk-module"
mkdir -p "$MOD"
cp "$W/mount.apk" "$MOD/patched.apk"
cat > "$MOD/module.prop" <<'EOF'
id=magis624_no_upgrade
name=Magis 6.2.4 - No Upgrade Dialog
version=1.0
versionCode=1
author=Local test
summary=Keeps official Magis 6.2.4 installed and bind-mounts the tested update-gate patch.
EOF
cat > "$MOD/service.sh" <<'EOF'
#!/system/bin/sh
MODDIR=${0%/*}
PKG=com.msandroid.mobile
i=0
while [ "$i" -lt 120 ]; do
  BASE=$(pm path "$PKG" 2>/dev/null | sed -n 's/^package://p' | head -n 1)
  [ -n "$BASE" ] && break
  sleep 1
  i=$((i+1))
done
[ -n "$BASE" ] || exit 0
VC=$(dumpsys package "$PKG" 2>/dev/null | sed -n 's/.*versionCode=\([0-9]*\).*/\1/p' | head -n 1)
[ "$VC" = '60204' ] || exit 0
am force-stop "$PKG" >/dev/null 2>&1
mount --bind "$MODDIR/patched.apk" "$BASE"
EOF
chmod 0755 "$MOD/service.sh"
(cd "$MOD" && zip -qr ../Magis-6.2.4-SIN-ACTUALIZACION-MAGISK-TESTED.zip .)
sha256sum "$OUT/Magis-6.2.4-SIN-ACTUALIZACION-MAGISK-TESTED.zip" > "$OUT/magisk-tested.sha256"
adb logcat -d -v threadtime > "$OUT/final-logcat.txt" || true
echo 'STATIC_PATCH_FOUND' | tee "$OUT/result.txt"
exit 0
