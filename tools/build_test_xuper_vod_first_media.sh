#!/usr/bin/env bash
set -euo pipefail
PKG='com.msandroid.mobile'
SRC='Magis-6.2.4.apk'
OUT='diagnostics-vod-first-media'
WORK='/tmp/xuper-vod-first-media'
mkdir -p "$OUT"
rm -rf "$WORK"
mkdir -p "$WORK"

APKSIGNER=$(find "$ANDROID_HOME/build-tools" -type f -name apksigner | sort -V | tail -1)
ZIPALIGN=$(find "$ANDROID_HOME/build-tools" -type f -name zipalign | sort -V | tail -1)
AAPT=$(find "$ANDROID_HOME/build-tools" -type f -name aapt | sort -V | tail -1)
APKTOOL="$RUNNER_TEMP/apktool.jar"
curl -fL --retry 4 --retry-all-errors https://github.com/iBotPeaches/Apktool/releases/download/v3.0.3/apktool_3.0.3.jar -o "$APKTOOL"

echo 'Decoding APK...'
java -jar "$APKTOOL" d -f "$SRC" -o "$WORK/proj" > "$OUT/apktool-decode.txt" 2>&1

# Keep the already validated update-gate identity while patching VOD.
python3 - "$WORK/proj/apktool.yml" <<'PY'
import re,sys
p=sys.argv[1]
s=open(p,encoding='utf-8').read()
s=re.sub(r'(?m)^\s*versionCode:\s*.*$', '  versionCode: 60505', s)
s=re.sub(r'(?m)^\s*versionName:\s*.*$', "  versionName: '6.5.5'", s)
open(p,'w',encoding='utf-8',newline='\n').write(s)
PY

# Dynamic discovery: locate the actual obfuscated method that consumes Program.medias
# and produces a Media name/URI. This avoids relying on d6/i2.p4 names.
python3 - "$WORK/proj" "$OUT" <<'PY'
import os,re,sys
root,out=sys.argv[1],sys.argv[2]
candidates=[]
method_re=re.compile(r'(?ms)^\.method\s+([^\n]+).*?^\.end method')
for dp,_,fs in os.walk(root):
    if '/smali' not in dp.replace('\\','/'):
        continue
    for fn in fs:
        if not fn.endswith('.smali'): continue
        p=os.path.join(dp,fn)
        try:s=open(p,encoding='utf-8').read()
        except:continue
        for m in method_re.finditer(s):
            block=m.group(0)
            if 'Lcom/titan/ranger/bean/Program;->getMedias()Ljava/util/List;' not in block:
                continue
            if 'Lcom/titan/ranger/bean/Media;->getName()Ljava/lang/String;' not in block:
                continue
            if ')Ljava/lang/String;' not in block:
                continue
            inv=re.search(r'invoke-virtual\s+\{(p\d+)\},\s+Lcom/titan/ranger/bean/Program;->getMedias\(\)Ljava/util/List;',block)
            if not inv: continue
            preg=inv.group(1)
            candidates.append((len(block),p,m.start(),m.end(),m.group(0).splitlines()[0],preg,block))

with open(os.path.join(out,'vod-method-candidates.txt'),'w',encoding='utf-8') as f:
    for c in sorted(candidates):
        f.write(f'{c[1]} :: {c[4]} :: ProgramReg={c[5]} :: bytes={c[0]}\n')

if not candidates:
    print('PATCH_TARGET=NOT_FOUND')
    open(os.path.join(out,'result.txt'),'w').write('PATCH_TARGET=NOT_FOUND\n')
    raise SystemExit(10)

# Prefer the smallest matching String-returning method: usually the media resolver itself.
_,p,start,end,decl,preg,old=sorted(candidates)[0]
print('PATCH_TARGET='+p)
print('PATCH_METHOD='+decl)
print('PROGRAM_REGISTER='+preg)
open(os.path.join(out,'target.before.smali'),'w',encoding='utf-8').write(old)

# Preserve the exact method declaration/signature; replace only implementation.
replacement = decl + f'''\n    .locals 4\n\n    const/4 v0, 0x0\n    if-eqz {preg}, :done\n\n    invoke-virtual {{{preg}}}, Lcom/titan/ranger/bean/Program;->getMedias()Ljava/util/List;\n    move-result-object v1\n    if-eqz v1, :done\n\n    invoke-interface {{v1}}, Ljava/util/List;->isEmpty()Z\n    move-result v2\n    if-nez v2, :done\n\n    const/4 v2, 0x0\n    invoke-interface {{v1, v2}}, Ljava/util/List;->get(I)Ljava/lang/Object;\n    move-result-object v1\n    check-cast v1, Lcom/titan/ranger/bean/Media;\n    if-eqz v1, :done\n\n    invoke-virtual {{v1}}, Lcom/titan/ranger/bean/Media;->getName()Ljava/lang/String;\n    move-result-object v0\n\n    const-string/jumbo v2, "XUPER_VOD_FIX"\n    const-string/jumbo v3, "Passing first backend-provided media URI to player"\n    invoke-static {{v2, v3}}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I\n\n    :done\n    return-object v0\n.end method'''

s=open(p,encoding='utf-8').read()
s2=s[:start]+replacement+s[end:]
open(p,'w',encoding='utf-8',newline='\n').write(s2)
open(os.path.join(out,'target.after.smali'),'w',encoding='utf-8').write(replacement)
with open(os.path.join(out,'result.txt'),'w') as f:
    f.write('PATCH_TARGET='+p+'\n')
    f.write('PATCH_METHOD='+decl+'\n')
    f.write('PROGRAM_REGISTER='+preg+'\n')
    f.write('PATCHED=PASS\n')
PY

echo 'Building APK...'
java -jar "$APKTOOL" b "$WORK/proj" -o "$WORK/unsigned.apk" > "$OUT/apktool-build.txt" 2>&1
"$ZIPALIGN" -f -p 4 "$WORK/unsigned.apk" "$WORK/aligned.apk"
keytool -genkeypair -noprompt -keystore "$WORK/test.jks" -storepass android -keypass android -alias patch -dname 'CN=XuperVODFix,O=LocalTest,C=MX' -keyalg RSA -keysize 2048 -validity 10000 >/dev/null 2>&1
CANDIDATE="$OUT/Xuper-6.5.5-VOD-PlayerFallback-Tested.apk"
"$APKSIGNER" sign --ks "$WORK/test.jks" --ks-key-alias patch --ks-pass pass:android --key-pass pass:android --out "$CANDIDATE" "$WORK/aligned.apk"
"$APKSIGNER" verify --verbose "$CANDIDATE" > "$OUT/signature-verify.txt"
"$AAPT" dump badging "$CANDIDATE" > "$OUT/badging.txt"
sha256sum "$CANDIDATE" > "$OUT/candidate.sha256"

capture(){ adb logcat -d -v threadtime > "$OUT/logcat.txt" 2>/dev/null || true; grep -E 'XUPER_VOD_FIX|FATAL EXCEPTION|AndroidRuntime|com\.msandroid\.mobile|SIGSEGV|Fatal signal' "$OUT/logcat.txt" | tail -500 > "$OUT/runtime-summary.txt" || true; }
trap capture EXIT
adb wait-for-device
adb uninstall "$PKG" >/dev/null 2>&1 || true
adb logcat -c || true
if ! adb install -g "$CANDIDATE" > "$OUT/install.txt" 2>&1; then echo 'INSTALL=FAIL' | tee -a "$OUT/result.txt"; exit 20; fi
echo 'INSTALL=PASS' | tee -a "$OUT/result.txt"
for perm in android.permission.READ_MEDIA_AUDIO android.permission.READ_MEDIA_IMAGES android.permission.POST_NOTIFICATIONS android.permission.CAMERA; do adb shell pm grant "$PKG" "$perm" >/dev/null 2>&1 || true; done
adb shell appops set "$PKG" MANAGE_EXTERNAL_STORAGE allow >/dev/null 2>&1 || true
adb shell am force-stop "$PKG" || true
timeout 20s adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > "$OUT/launch.txt" 2>&1 || true
sleep 20
PID=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r[:space:]' || true)
adb shell dumpsys activity activities > "$OUT/activities-20s.txt" || true
if [ -n "$PID" ]; then echo 'ALIVE_20=PASS' | tee -a "$OUT/result.txt"; else echo 'ALIVE_20=FAIL' | tee -a "$OUT/result.txt"; exit 21; fi
if grep -E 'topResumedActivity|mResumedActivity' "$OUT/activities-20s.txt" | head -5 | grep -q 'MainAty'; then echo 'MAINATY_20=PASS' | tee -a "$OUT/result.txt"; else echo 'MAINATY_20=FAIL' | tee -a "$OUT/result.txt"; exit 22; fi
sleep 40
PID=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r[:space:]' || true)
adb shell dumpsys activity activities > "$OUT/activities-60s.txt" || true
if [ -n "$PID" ]; then echo 'ALIVE_60=PASS' | tee -a "$OUT/result.txt"; else echo 'ALIVE_60=FAIL' | tee -a "$OUT/result.txt"; exit 23; fi
if grep -E 'topResumedActivity|mResumedActivity' "$OUT/activities-60s.txt" | head -5 | grep -q 'MainAty'; then echo 'MAINATY_60=PASS' | tee -a "$OUT/result.txt"; else echo 'MAINATY_60=FAIL' | tee -a "$OUT/result.txt"; exit 24; fi
capture
trap - EXIT
echo 'VALIDATED=PASS' | tee -a "$OUT/result.txt"
