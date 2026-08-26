#!/usr/bin/env bash
set -euo pipefail

# This runner is intentionally MAGIS 6.2.4 ONLY.
# It never downloads or installs 6.5.5. The old workflow name is reused only
# because that Android-16 emulator job is already known to execute reliably.
PKG='com.msandroid.mobile'
OUT='diagnostics-update'
TARGET_CODE='60204'
TARGET_NAME='6.2.4'
mkdir -p "$OUT/candidates" "$OUT/static-tests" "$OUT/dexdump"

AAPT=$(find "$ANDROID_HOME/build-tools" -type f -name aapt | sort -V | tail -1)
APKSIGNER=$(find "$ANDROID_HOME/build-tools" -type f -name apksigner | sort -V | tail -1)
ZIPALIGN=$(find "$ANDROID_HOME/build-tools" -type f -name zipalign | sort -V | tail -1)

EXPECTED_CERT=$($APKSIGNER verify --print-certs magis-current.apk 2>/dev/null | sed -n 's/.*certificate SHA-256 digest: //p' | head -1 | tr -d ':[:space:]' | tr '[:upper:]' '[:lower:]')
echo "expected_cert=$EXPECTED_CERT" | tee "$OUT/expected-cert.txt"
[[ "$EXPECTED_CERT" == 'd30dc60fd8625d49fa4e82eb442c9307743f9621004b94e229dcc01f6a9035ff' ]] || exit 70

validate_624() {
  local f="$1" tag="$2"
  unzip -t "$f" >/dev/null 2>&1 || return 1
  "$AAPT" dump badging "$f" > "$OUT/candidates/${tag}-badging.txt" 2>&1 || return 1
  grep -q "package: name='$PKG' versionCode='$TARGET_CODE' versionName='$TARGET_NAME'" "$OUT/candidates/${tag}-badging.txt" || return 1
  "$APKSIGNER" verify --verbose --print-certs "$f" > "$OUT/candidates/${tag}-signing.txt" 2>&1 || return 1
  local cert
  cert=$($APKSIGNER verify --print-certs "$f" 2>/dev/null | sed -n 's/.*certificate SHA-256 digest: //p' | head -1 | tr -d ':[:space:]' | tr '[:upper:]' '[:lower:]')
  [[ "$cert" == "$EXPECTED_CERT" ]] || return 1
  sha256sum "$f" > "$OUT/candidates/${tag}-sha256.txt"
}

SOURCES=(
  'https://aftv.news/4721725'
  'https://aftvnews.com/4721725'
  'https://www.aftvnews.com/4721725'
  'https://go.aftvnews.com/4721725'
  'https://appteka.store/apps/cb8r309715/download'
)
APK624='Magis-6.2.4.apk'
rm -f "$APK624"
for i in "${!SOURCES[@]}"; do
  src="${SOURCES[$i]}"; tag="source-$((i+1))"; f="$OUT/candidates/${tag}.bin"
  echo "TRY_624 $src" | tee -a "$OUT/actions.txt"
  if curl -fL --retry 3 --retry-all-errors --connect-timeout 15 --max-time 180 -A 'Mozilla/5.0 (Linux; Android 16; Pixel 6)' "$src" -o "$f" \
      >"$OUT/candidates/${tag}-curl-stdout.txt" 2>"$OUT/candidates/${tag}-curl-stderr.txt"; then
    if validate_624 "$f" "$tag"; then cp "$f" "$APK624"; echo "ACCEPTED_624 $src" | tee -a "$OUT/actions.txt"; break; fi
  fi
done
[[ -s "$APK624" ]] || { echo NO_OFFICIAL_624_SOURCE_FOUND >&2; exit 71; }
"$AAPT" dump badging "$APK624" | tee "$OUT/magis624-badging.txt"
"$APKSIGNER" verify --verbose --print-certs "$APK624" | tee "$OUT/magis624-signing.txt"
sha256sum "$APK624" | tee "$OUT/magis624-sha256.txt"

# Generate a local test signer. The official 6.2.4 remains the installed package;
# signed variants are bind-mounted over it first, so PackageManager keeps the
# official package/signing identity during the primary test.
keytool -genkeypair -noprompt -keystore /tmp/patch.jks -storepass android -keypass android -alias patch \
  -dname 'CN=Magis624RuntimePatch,O=LocalTest,C=MX' -keyalg RSA -keysize 2048 -validity 10000 >/dev/null 2>&1

make_variant() {
  local mode="$1" out="$2"
  local work="$OUT/static-tests/${mode}"
  mkdir -p "$work"
  python3 - "$APK624" "$work/unsigned.apk" "$mode" "$work/replacements.txt" <<'PY'
import sys, zipfile, hashlib, zlib, os
src,out,mode,report=sys.argv[1:]
repls=[]
if mode == 'endpoint':
    repls=[(b'api/portalCore/box/update', b'api/portalCore/box/updatx')]
elif mode == 'flags':
    repls=[(b'forceUpdate', b'forceUpdatx'), (b'hasNewVersion', b'hasOldVersion')]
elif mode == 'combo':
    repls=[(b'api/portalCore/box/update', b'api/portalCore/box/updatx'),
           (b'forceUpdate', b'forceUpdatx'), (b'hasNewVersion', b'hasOldVersion'),
           (b'upgradeVerCode', b'upgradeVerCodx')]
else:
    raise SystemExit('bad mode')
with zipfile.ZipFile(src,'r') as zin:
    dex=bytearray(zin.read('classes.dex'))
    lines=[]
    for a,b in repls:
        if len(a)!=len(b): raise SystemExit('length mismatch')
        n=dex.count(a)
        lines.append(f'{a.decode()} -> {b.decode()} count={n}')
        if n:
            dex=dex.replace(a,b)
    # Standard DEX integrity fields cover the whole packed classes.dex.
    dex[12:32]=hashlib.sha1(dex[32:]).digest()
    dex[8:12]=(zlib.adler32(dex[12:]) & 0xffffffff).to_bytes(4,'little')
    with zipfile.ZipFile(out,'w',allowZip64=True) as zout:
        for info in zin.infolist():
            name=info.filename
            if name.upper().startswith('META-INF/') and name.upper().endswith(('.RSA','.DSA','.EC','.SF','MANIFEST.MF')):
                continue
            data=bytes(dex) if name=='classes.dex' else zin.read(name)
            ni=zipfile.ZipInfo(name, date_time=info.date_time)
            ni.compress_type=info.compress_type; ni.comment=info.comment; ni.extra=info.extra
            ni.internal_attr=info.internal_attr; ni.external_attr=info.external_attr; ni.create_system=info.create_system
            zout.writestr(ni,data)
open(report,'w').write('\n'.join(lines)+'\n')
PY
  "$ZIPALIGN" -f -p 4 "$work/unsigned.apk" "$work/aligned.apk"
  "$APKSIGNER" sign --ks /tmp/patch.jks --ks-key-alias patch --ks-pass pass:android --key-pass pass:android \
    --out "$out" "$work/aligned.apk"
  "$APKSIGNER" verify --verbose --print-certs "$out" > "$work/signing.txt"
  sha256sum "$out" > "$work/sha256.txt"
  cat "$work/replacements.txt"
}

make_variant endpoint "$OUT/static-tests/Magis-6.2.4-endpoint.apk"
make_variant flags "$OUT/static-tests/Magis-6.2.4-flags.apk"
make_variant combo "$OUT/static-tests/Magis-6.2.4-combo.apk"

adb root || true
adb wait-for-device
adb shell setenforce 0 || true
adb install -r -g "$APK624" | tee "$OUT/install-624.txt"
adb shell pm clear "$PKG" || true
BASE=$(adb shell pm path "$PKG" | sed -n 's/^package://p' | head -1 | tr -d '\r')
echo "base=$BASE" | tee "$OUT/base-path.txt"
[[ -n "$BASE" ]] || exit 72

ui_has_gate() {
  local f="$1"
  grep -Eiq 'Actualizaci[oó]n de versi[oó]n|Version Upgrade|V6\.5\.5|6\.5\.5|gaeg\.xvmobdes\.com/download' "$f"
}

test_bind_variant() {
  local mode="$1" apk="$2" dir="$OUT/static-tests/$mode"
  mkdir -p "$dir"
  adb shell am force-stop "$PKG" || true
  adb push "$apk" "/data/local/tmp/magis-${mode}.apk" >/dev/null
  adb shell "umount '$BASE' 2>/dev/null || true"
  adb shell "mount -o bind '/data/local/tmp/magis-${mode}.apk' '$BASE'"
  adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
  sleep 20
  adb shell pidof "$PKG" | tee "$dir/pid20.txt" || true
  adb shell uiautomator dump "/sdcard/ui-${mode}.xml" >/dev/null 2>&1 || true
  adb pull "/sdcard/ui-${mode}.xml" "$dir/ui20.xml" >/dev/null 2>&1 || true
  adb exec-out screencap -p > "$dir/screen20.png" || true
  local pid20; pid20=$(cat "$dir/pid20.txt" | tr -d '\r[:space:]' || true)
  if [[ -z "$pid20" ]] || ui_has_gate "$dir/ui20.xml"; then
    echo "$mode bind_test=FAIL_20" | tee "$dir/result.txt"
    return 1
  fi
  sleep 40
  adb shell pidof "$PKG" | tee "$dir/pid60.txt" || true
  adb shell uiautomator dump "/sdcard/ui-${mode}-60.xml" >/dev/null 2>&1 || true
  adb pull "/sdcard/ui-${mode}-60.xml" "$dir/ui60.xml" >/dev/null 2>&1 || true
  adb exec-out screencap -p > "$dir/screen60.png" || true
  local pid60; pid60=$(cat "$dir/pid60.txt" | tr -d '\r[:space:]' || true)
  if [[ -z "$pid60" ]] || ui_has_gate "$dir/ui60.xml"; then
    echo "$mode bind_test=FAIL_60" | tee "$dir/result.txt"
    return 1
  fi
  echo "$mode bind_test=PASS" | tee "$dir/result.txt"
  return 0
}

PASS_MODE=''
for mode in endpoint flags combo; do
  if test_bind_variant "$mode" "$OUT/static-tests/Magis-6.2.4-${mode}.apk"; then PASS_MODE="$mode"; break; fi
done

if [[ -n "$PASS_MODE" ]]; then
  WINNER="$OUT/static-tests/Magis-6.2.4-${PASS_MODE}.apk"
  cp "$WINNER" "$OUT/Magis-6.2.4-SIN-CUADRO-runtime.apk"
  echo "winner=$PASS_MODE" | tee "$OUT/static-winner.txt"

  # Verify whether the same APK can also run as a normal standalone install.
  adb shell am force-stop "$PKG" || true
  adb shell "umount '$BASE' 2>/dev/null || true"
  adb uninstall "$PKG" >/dev/null 2>&1 || true
  if adb install -g "$WINNER" > "$OUT/standalone-install.txt" 2>&1; then
    adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
    sleep 20
    adb shell pidof "$PKG" | tee "$OUT/standalone-pid.txt" || true
    adb shell uiautomator dump /sdcard/standalone.xml >/dev/null 2>&1 || true
    adb pull /sdcard/standalone.xml "$OUT/standalone-ui.xml" >/dev/null 2>&1 || true
    adb exec-out screencap -p > "$OUT/standalone-screen.png" || true
    SPID=$(cat "$OUT/standalone-pid.txt" | tr -d '\r[:space:]' || true)
    if [[ -n "$SPID" ]] && ! ui_has_gate "$OUT/standalone-ui.xml"; then
      echo standalone=PASS | tee "$OUT/standalone-result.txt"
      cp "$WINNER" "$OUT/Magis-6.2.4-SIN-ACTUALIZACION-STANDALONE.apk"
    else
      echo standalone=FAIL_RUNTIME_OR_GATE | tee "$OUT/standalone-result.txt"
    fi
  else
    echo standalone=FAIL_INSTALL | tee "$OUT/standalone-result.txt"
  fi

  # Always package the successful bind-mount form as a Magisk module. It keeps
  # the user's installed official Magis 6.2.4 as the actual package identity.
  MOD="$OUT/magisk-module"
  mkdir -p "$MOD"
  cp "$WINNER" "$MOD/patched.apk"
  cat > "$MOD/module.prop" <<'EOF'
id=magis624_no_upgrade
name=Magis 6.2.4 - No Upgrade Dialog
version=1.0
versionCode=1
author=ChatGPT + Carlos
summary=Keeps official Magis 6.2.4 installed and bind-mounts only the tested update-gate patch.
EOF
  cat > "$MOD/service.sh" <<'EOF'
#!/system/bin/sh
MODDIR=${0%/*}
PKG=com.msandroid.mobile
# Wait for Android package service.
i=0
while [ "$i" -lt 120 ]; do
  BASE=$(pm path "$PKG" 2>/dev/null | sed -n 's/^package://p' | head -n 1)
  [ -n "$BASE" ] && break
  sleep 1
  i=$((i+1))
done
[ -n "$BASE" ] || exit 0
VC=$(dumpsys package "$PKG" 2>/dev/null | sed -n 's/.*versionCode=\([0-9]*\).*/\1/p' | head -n 1)
[ "$VC" = "60204" ] || exit 0
am force-stop "$PKG" >/dev/null 2>&1
mount -o bind "$MODDIR/patched.apk" "$BASE"
EOF
  chmod 0755 "$MOD/service.sh"
  (cd "$MOD" && zip -qr ../Magis-6.2.4-SIN-ACTUALIZACION-MAGISK.zip .)
  sha256sum "$OUT/Magis-6.2.4-SIN-ACTUALIZACION-MAGISK.zip" > "$OUT/Magis-6.2.4-SIN-ACTUALIZACION-MAGISK.sha256"
  echo 'STATIC_PATCH_FOUND' | tee "$OUT/result.txt"
  # Intentional non-zero: prevents the obsolete workflow's 6.5.5 post-step.
  exit 86
fi

# No static variant worked. Fall back to runtime unpacking of the same 6.2.4
# so the exact force-update method can be patched next.
adb uninstall "$PKG" >/dev/null 2>&1 || true
adb install -r -g "$APK624" | tee "$OUT/reinstall-official-before-dump.txt"
adb shell pm clear "$PKG" || true
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
sleep 18
FRIDA_VERSION='17.2.17'
python3 -m venv /tmp/frida-venv
source /tmp/frida-venv/bin/activate
python -m pip install --upgrade pip >/dev/null
python -m pip install "frida==$FRIDA_VERSION" frida-tools frida-dexdump
curl -fL --retry 3 --retry-all-errors "https://github.com/frida/frida/releases/download/${FRIDA_VERSION}/frida-server-${FRIDA_VERSION}-android-x86_64.xz" -o /tmp/frida-server.xz
xz -dc /tmp/frida-server.xz > /tmp/frida-server
chmod +x /tmp/frida-server
adb push /tmp/frida-server /data/local/tmp/frida-server >/dev/null
adb shell chmod 755 /data/local/tmp/frida-server
adb shell 'pkill -9 frida-server || true; nohup /data/local/tmp/frida-server >/data/local/tmp/frida-server.log 2>&1 &' || true
sleep 4
frida-ps -Uai | tee "$OUT/frida-ps.txt" || true
adb shell am force-stop "$PKG" || true
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
sleep 15
set +e
frida-dexdump -U -n "$PKG" -o "$OUT/dexdump" 2>&1 | tee "$OUT/frida-dexdump.txt"
DEX_RC=${PIPESTATUS[0]}
set -e
echo "frida_dexdump_rc=$DEX_RC" | tee "$OUT/frida-dexdump-rc.txt"
find "$OUT/dexdump" -type f -name '*.dex' -print -exec sha256sum {} \; | tee "$OUT/dex-files.txt" || true
COUNT=$(find "$OUT/dexdump" -type f -name '*.dex' | wc -l | tr -d ' ')
echo "dex_count=$COUNT" | tee "$OUT/dex-count.txt"
grep -RIna --binary-files=text -E 'handleForceUpgrade|handleUpgradeBussiness|CommonUpgradeDialog|UpgradeDialog|forceUpdate|getForceUpdate|hasNewVersion|dialog_common_upgrade|upgradeVerCode|getUpgradeVerCode' "$OUT/dexdump" > "$OUT/upgrade-symbol-hits.txt" || true
[[ "$COUNT" -gt 0 ]] || { echo RUNTIME_DEX_DUMP_EMPTY >&2; exit 73; }
echo 'MAGIS_624_RUNTIME_DEX_DUMP_COMPLETE_NO_UPDATE_PERFORMED' | tee "$OUT/result.txt"
exit 86
