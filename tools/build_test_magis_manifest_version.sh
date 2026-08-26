#!/usr/bin/env bash
set -euo pipefail

PKG='com.msandroid.mobile'
SRC='Magis-6.2.4.apk'
OUT='diagnostics-manifest-version'
WORK='/tmp/magis-manifest-work'
VERSION_CODE='900000'
mkdir -p "$OUT" "$WORK/patch"

APKSIGNER=$(find "$ANDROID_HOME/build-tools" -type f -name apksigner | sort -V | tail -1)
ZIPALIGN=$(find "$ANDROID_HOME/build-tools" -type f -name zipalign | sort -V | tail -1)
AAPT=$(find "$ANDROID_HOME/build-tools" -type f -name aapt | sort -V | tail -1)

# Patch the compiled AndroidManifest.xml directly; do not rebuild resources or DEX.
unzip -p "$SRC" AndroidManifest.xml > "$WORK/patch/AndroidManifest.xml"
cp "$WORK/patch/AndroidManifest.xml" "$OUT/AndroidManifest.binary.before"
python3 - "$WORK/patch/AndroidManifest.xml" "$VERSION_CODE" > "$OUT/binary-manifest-patch.txt" <<'PY'
import struct, sys
p=sys.argv[1]
new_code=int(sys.argv[2])
b=bytearray(open(p,'rb').read())
RES_XML_RESOURCE_MAP_TYPE=0x0180
RES_XML_START_ELEMENT_TYPE=0x0102
ANDROID_VERSION_CODE=0x0101021b
TYPE_INT_DEC=0x10
TYPE_INT_HEX=0x11
u16=lambda o: struct.unpack_from('<H',b,o)[0]
u32=lambda o: struct.unpack_from('<I',b,o)[0]
if len(b)<8 or u16(0)!=0x0003:
    raise SystemExit('not binary Android XML')
resource_map=[]; patched=[]; o=8
while o+8<=len(b):
    typ=u16(o); hsz=u16(o+2); size=u32(o+4)
    if size<hsz or size<8 or o+size>len(b):
        raise SystemExit(f'bad chunk at {o}: type={typ:#x} hsz={hsz} size={size}')
    if typ==RES_XML_RESOURCE_MAP_TYPE:
        resource_map=[u32(x) for x in range(o+hsz,o+size,4)]
        print(f'resource_map_entries={len(resource_map)}')
    elif typ==RES_XML_START_ELEMENT_TYPE:
        ext=o+16
        if ext+20<=o+size:
            attr_start=u16(ext+8); attr_size=u16(ext+10); attr_count=u16(ext+12)
            base=ext+attr_start
            for i in range(attr_count):
                a=base+i*attr_size
                if a+20>o+size: break
                name_idx=u32(a+4)
                rid=resource_map[name_idx] if name_idx<len(resource_map) else 0
                if rid==ANDROID_VERSION_CODE:
                    dtype=b[a+15]; old=u32(a+16)
                    if dtype not in (TYPE_INT_DEC,TYPE_INT_HEX):
                        raise SystemExit(f'unexpected versionCode data type {dtype:#x}')
                    struct.pack_into('<I',b,a+16,new_code)
                    patched.append((a+16,old,new_code,dtype))
                    print(f'patched_versionCode_offset={a+16} old={old} new={new_code} type={dtype:#x}')
    o+=size
if len(patched)!=1:
    raise SystemExit(f'expected one versionCode, patched={len(patched)}')
open(p,'wb').write(b)
PY
cp "$WORK/patch/AndroidManifest.xml" "$OUT/AndroidManifest.binary.after"

# Update only AndroidManifest.xml inside a copy of the original archive.
cp "$SRC" "$WORK/candidate-unsigned.apk"
(cd "$WORK/patch" && zip -q -u "$WORK/candidate-unsigned.apk" AndroidManifest.xml)

# Runtime-sensitive payloads must remain byte-identical.
for entry in classes.dex resources.arsc; do
  unzip -p "$SRC" "$entry" | sha256sum | awk '{print $1}' > "$OUT/${entry}.source.sha256"
  unzip -p "$WORK/candidate-unsigned.apk" "$entry" | sha256sum | awk '{print $1}' > "$OUT/${entry}.candidate.sha256"
  diff -u "$OUT/${entry}.source.sha256" "$OUT/${entry}.candidate.sha256" > "$OUT/${entry}.diff.txt" || {
    echo "${entry}_IDENTICAL=FAIL" | tee -a "$OUT/result.txt"; exit 11;
  }
done
echo 'DEX_IDENTICAL=PASS' | tee "$OUT/result.txt"
echo 'RESOURCES_IDENTICAL=PASS' | tee -a "$OUT/result.txt"

zip -q -d "$WORK/candidate-unsigned.apk" 'META-INF/*.RSA' 'META-INF/*.DSA' 'META-INF/*.EC' 'META-INF/*.SF' 'META-INF/MANIFEST.MF' >/dev/null 2>&1 || true
keytool -genkeypair -noprompt -keystore /tmp/magis-manifest.jks -storepass android -keypass android -alias patch -dname 'CN=MagisManifestCandidate,O=LocalTest,C=MX' -keyalg RSA -keysize 2048 -validity 10000 >/dev/null 2>&1 || true
"$ZIPALIGN" -f -p 4 "$WORK/candidate-unsigned.apk" "$WORK/aligned.apk"
"$APKSIGNER" sign --ks /tmp/magis-manifest.jks --ks-key-alias patch --ks-pass pass:android --key-pass pass:android --out "$OUT/Magis-6.2.4-ManifestVersion900000-Tested.apk" "$WORK/aligned.apk"
"$APKSIGNER" verify --verbose "$OUT/Magis-6.2.4-ManifestVersion900000-Tested.apk" > "$OUT/signature-verify.txt"
"$AAPT" dump badging "$OUT/Magis-6.2.4-ManifestVersion900000-Tested.apk" > "$OUT/badging.txt"
grep -q "versionCode='900000'" "$OUT/badging.txt"
sha256sum "$OUT/Magis-6.2.4-ManifestVersion900000-Tested.apk" > "$OUT/candidate.sha256"

capture_diag() {
  adb logcat -d -v threadtime > "$OUT/logcat.txt" 2>/dev/null || true
  grep -E 'Fatal signal|SIGSEGV|FATAL EXCEPTION|AndroidRuntime|com\.msandroid\.mobile|play_station|DexHelper|dexjni' "$OUT/logcat.txt" | tail -400 > "$OUT/runtime-summary.txt" || true
}
trap capture_diag EXIT

adb wait-for-device
adb uninstall "$PKG" >/dev/null 2>&1 || true
adb logcat -c || true
if ! adb install -g "$OUT/Magis-6.2.4-ManifestVersion900000-Tested.apk" > "$OUT/install.txt" 2>&1; then
  echo 'INSTALL=FAIL' | tee -a "$OUT/result.txt"; exit 12;
fi
echo 'INSTALL=PASS' | tee -a "$OUT/result.txt"
for perm in android.permission.READ_MEDIA_AUDIO android.permission.READ_MEDIA_IMAGES android.permission.POST_NOTIFICATIONS android.permission.CAMERA; do
  adb shell pm grant "$PKG" "$perm" >/dev/null 2>&1 || true
done
adb shell appops set "$PKG" MANAGE_EXTERNAL_STORAGE allow >/dev/null 2>&1 || true
adb shell am force-stop "$PKG" >/dev/null 2>&1 || true
timeout 20s adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > "$OUT/launch.txt" 2>&1 || true

check_point() {
  local sec="$1" pid top
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
  fi
  echo "UPDATE_GATE_${sec}=PASS" | tee -a "$OUT/result.txt"
}

sleep 20
check_point 20
sleep 40
check_point 60
capture_diag
trap - EXIT
for marker in DEX_IDENTICAL RESOURCES_IDENTICAL INSTALL ALIVE_20 MAINATY_20 UPDATE_GATE_20 ALIVE_60 MAINATY_60 UPDATE_GATE_60; do
  grep -q "^${marker}=PASS$" "$OUT/result.txt" || { echo 'VALIDATED=FAIL' | tee -a "$OUT/result.txt"; exit 20; }
done
echo 'VALIDATED=PASS' | tee -a "$OUT/result.txt"
