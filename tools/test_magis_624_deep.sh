#!/usr/bin/env bash
set -euo pipefail
PKG='com.msandroid.mobile'
APK='Magis-6.2.4.apk'
OUT='diagnostics-deep'
mkdir -p "$OUT/static" "$OUT/frida" "$OUT/dexdump"

adb root || true
adb wait-for-device
adb shell setenforce 0 >/dev/null 2>&1 || true
adb emu geo fix -99.1332 19.4326 >/dev/null 2>&1 || true

permits() {
  adb shell pm grant "$PKG" android.permission.READ_MEDIA_AUDIO >/dev/null 2>&1 || true
  adb shell pm grant "$PKG" android.permission.READ_MEDIA_IMAGES >/dev/null 2>&1 || true
  adb shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true
  adb shell pm grant "$PKG" android.permission.CAMERA >/dev/null 2>&1 || true
  adb shell pm grant "$PKG" android.permission.READ_EXTERNAL_STORAGE >/dev/null 2>&1 || true
}
launch() {
  adb shell am force-stop "$PKG" >/dev/null 2>&1 || true
  timeout 15s adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
}
dump_state() {
  local tag="$1"
  timeout 8s adb shell uiautomator dump "/sdcard/${tag}.xml" >/dev/null 2>&1 || true
  timeout 8s adb pull "/sdcard/${tag}.xml" "$OUT/${tag}.xml" >/dev/null 2>&1 || true
  adb exec-out screencap -p > "$OUT/${tag}.png" || true
  adb shell pidof "$PKG" 2>/dev/null | tr -d '\r' > "$OUT/${tag}.pid" || true
}

# Install the exact official 6.2.4 recovered and verified by the workflow.
adb install -r -g "$APK" | tee "$OUT/install-official.txt"
adb shell pm clear "$PKG" >/dev/null 2>&1 || true
permits
launch
sleep 25
dump_state official25
BASE=$(adb shell pm path "$PKG" | sed -n 's/^package://p' | head -1 | tr -d '\r')
echo "base=$BASE" | tee "$OUT/base.txt"
[[ -n "$BASE" ]]

# Build three same-length classes.dex probes. They are NEVER directly installed
# in this phase; only bind-mounted over the already-installed official 6.2.4.
python3 - "$APK" "$OUT/static" <<'PY'
import sys,zipfile,hashlib,zlib,os
src,out=sys.argv[1:]
modes={
 'endpoint':[(b'api/portalCore/box/update',b'api/portalCore/box/updatx')],
 'flags':[(b'forceUpdate',b'forceUpdatx'),(b'hasNewVersion',b'hasOldVersion')],
 'combo':[(b'api/portalCore/box/update',b'api/portalCore/box/updatx'),(b'forceUpdate',b'forceUpdatx'),(b'hasNewVersion',b'hasOldVersion'),(b'upgradeVerCode',b'upgradeVerCodx')],
}
with zipfile.ZipFile(src) as zin:
  original=zin.read('classes.dex')
  infos=zin.infolist()
  for mode,repls in modes.items():
    dex=bytearray(original); report=[]
    for old,new in repls:
      n=dex.count(old); report.append(f'{old.decode()} -> {new.decode()} count={n}')
      if len(old)!=len(new): raise SystemExit('length mismatch')
      dex=dex.replace(old,new)
    dex[12:32]=hashlib.sha1(dex[32:]).digest()
    dex[8:12]=(zlib.adler32(dex[12:]) & 0xffffffff).to_bytes(4,'little')
    path=os.path.join(out,mode+'.apk')
    with zipfile.ZipFile(path,'w',allowZip64=True) as zout:
      for info in infos:
        data=bytes(dex) if info.filename=='classes.dex' else zin.read(info.filename)
        ni=zipfile.ZipInfo(info.filename,date_time=info.date_time)
        ni.compress_type=info.compress_type; ni.comment=info.comment; ni.extra=info.extra
        ni.internal_attr=info.internal_attr; ni.external_attr=info.external_attr; ni.create_system=info.create_system
        zout.writestr(ni,data)
    open(os.path.join(out,mode+'-replacements.txt'),'w').write('\n'.join(report)+'\n')
PY

# Even though CI cannot reproduce the Mexico update response, establish whether
# each probe survives SecNeo/runtime loading for 45 seconds.
for mode in endpoint flags combo; do
  echo "=== stability $mode ===" | tee -a "$OUT/static-results.txt"
  remote="/data/local/tmp/magis-${mode}.apk"
  adb shell am force-stop "$PKG" >/dev/null 2>&1 || true
  adb shell "umount '$BASE' 2>/dev/null || true"
  adb push "$OUT/static/${mode}.apk" "$remote" >/dev/null
  if ! adb shell "mount --bind '$remote' '$BASE'"; then
    echo "$mode=MOUNT_FAIL" | tee -a "$OUT/static-results.txt"
    continue
  fi
  adb shell pm clear "$PKG" >/dev/null 2>&1 || true
  permits
  launch
  sleep 20
  dump_state "${mode}20"
  sleep 25
  dump_state "${mode}45"
  P20=$(cat "$OUT/${mode}20.pid" 2>/dev/null | tr -d '[:space:]' || true)
  P45=$(cat "$OUT/${mode}45.pid" 2>/dev/null | tr -d '[:space:]' || true)
  if [[ -n "$P20" && -n "$P45" ]]; then
    echo "$mode=RUNTIME_STABLE" | tee -a "$OUT/static-results.txt"
  else
    echo "$mode=RUNTIME_DEAD" | tee -a "$OUT/static-results.txt"
  fi
  adb shell am force-stop "$PKG" >/dev/null 2>&1 || true
  adb shell "umount '$BASE' 2>/dev/null || true"
done

# Return to pristine official APK before inspecting classes in memory.
adb uninstall "$PKG" >/dev/null 2>&1 || true
adb install -g "$APK" | tee "$OUT/reinstall-official.txt"
adb shell pm clear "$PKG" >/dev/null 2>&1 || true
permits
launch
sleep 20

python3 -m venv /tmp/frida-venv
source /tmp/frida-venv/bin/activate
python -m pip install -q --upgrade pip
python -m pip install -q frida-tools frida-dexdump
FRIDA_VERSION=$(python - <<'PY'
import frida
print(frida.__version__)
PY
)
echo "frida_version=$FRIDA_VERSION" | tee "$OUT/frida/version.txt"
ABI=$(adb shell getprop ro.product.cpu.abi | tr -d '\r')
echo "device_abi=$ABI" | tee "$OUT/frida/abi.txt"
case "$ABI" in
  x86_64) FABI=x86_64 ;;
  arm64-v8a) FABI=arm64 ;;
  *) echo "UNSUPPORTED_FRIDA_ABI=$ABI" | tee "$OUT/frida/error.txt"; exit 0 ;;
esac
curl -fL --retry 3 --retry-all-errors \
  "https://github.com/frida/frida/releases/download/${FRIDA_VERSION}/frida-server-${FRIDA_VERSION}-android-${FABI}.xz" \
  -o /tmp/frida-server.xz
xz -dc /tmp/frida-server.xz > /tmp/frida-server
chmod +x /tmp/frida-server
adb push /tmp/frida-server /data/local/tmp/frida-server >/dev/null
adb shell chmod 755 /data/local/tmp/frida-server
adb shell 'pkill -f frida-server 2>/dev/null || true'
adb shell '/data/local/tmp/frida-server >/data/local/tmp/frida-server.log 2>&1 &' || true
sleep 3
frida-ps -Uai > "$OUT/frida/processes.txt" 2>&1 || true

cat > /tmp/list-update-classes.js <<'JS'
Java.perform(function () {
  var classes = Java.enumerateLoadedClassesSync();
  classes.sort();
  classes.forEach(function (name) {
    var l = name.toLowerCase();
    if (l.indexOf('update') >= 0 || l.indexOf('upgrade') >= 0 || l.indexOf('mobile.bean') >= 0 || l.indexOf('brasiltv') >= 0) {
      console.log('CLASS ' + name);
      try {
        var C = Java.use(name);
        var ms = C.class.getDeclaredMethods();
        for (var i=0;i<ms.length;i++) console.log('METHOD ' + ms[i].toString());
      } catch (e) {
        console.log('INTROSPECT_ERROR ' + name + ' ' + e);
      }
    }
  });
});
JS

timeout 30s frida -U -n "$PKG" -q -l /tmp/list-update-classes.js > "$OUT/frida/update-classes.txt" 2>&1 || true

# Dump any DEX currently mapped after the protection layer has initialized.
timeout 150s frida-dexdump -U -n "$PKG" -o "$OUT/dexdump" > "$OUT/frida/dexdump.log" 2>&1 || true
find "$OUT/dexdump" -type f -maxdepth 2 -print | sort > "$OUT/dexdump-files.txt" || true
python3 - "$OUT/dexdump" "$OUT/dexdump-hits.txt" <<'PY'
import os,sys
root,out=sys.argv[1:]
need=[b'forceUpdate',b'hasNewVersion',b'upgradeVerCode',b'UpgradeDialog',b'handleForceUpgrade',b'api/portalCore/box/update',b'UpdateBean']
rows=[]
for dp,_,fs in os.walk(root):
  for fn in fs:
    p=os.path.join(dp,fn)
    try: d=open(p,'rb').read()
    except: continue
    hits=[x.decode() for x in need if x in d]
    if hits: rows.append(f'{p}: '+', '.join(hits))
open(out,'w').write('\n'.join(rows)+'\n')
PY
cat "$OUT/static-results.txt" || true
cat "$OUT/dexdump-hits.txt" || true
adb logcat -d -v threadtime | grep -Ei 'com\.msandroid\.mobile|AndroidRuntime|FATAL EXCEPTION|SecNeo|Bangcle|ijiami' | tail -1500 > "$OUT/logcat.txt" || true
