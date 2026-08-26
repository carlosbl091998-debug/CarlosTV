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

I2=$(find "$WORK/proj" -type f -path '*/d6/i2.smali' | head -1 || true)
if [ -z "$I2" ]; then
  echo 'PATCH_TARGET=NOT_FOUND' | tee "$OUT/result.txt"
  find "$WORK/proj" -type f -name 'i2.smali' | head -50 > "$OUT/i2-candidates.txt"
  exit 10
fi
echo "PATCH_TARGET=$I2" | tee "$OUT/result.txt"
cp "$I2" "$OUT/i2.before.smali"

python3 - "$I2" <<'PY' > "$OUT/patch.txt"
import re,sys
p=sys.argv[1]
s=open(p,encoding='utf-8').read()
pat=r'(?ms)^\.method public final p4\(Lcom/titan/ranger/bean/Program;Lr6/a;Z\)Ljava/lang/String;.*?^\.end method'
m=re.search(pat,s)
if not m:
    raise SystemExit('p4 target method not found')
# Conservative fallback: if Program.medias has at least one Media, return its real name.
# If medias is null/empty, return null so the existing caller can keep its normal failure path.
rep=r'''.method public final p4(Lcom/titan/ranger/bean/Program;Lr6/a;Z)Ljava/lang/String;
    .locals 4

    const/4 v0, 0x0
    if-eqz p1, :done

    invoke-virtual {p1}, Lcom/titan/ranger/bean/Program;->getMedias()Ljava/util/List;
    move-result-object v1
    if-eqz v1, :done

    invoke-interface {v1}, Ljava/util/List;->isEmpty()Z
    move-result v2
    if-nez v2, :done

    const/4 v2, 0x0
    invoke-interface {v1, v2}, Ljava/util/List;->get(I)Ljava/lang/Object;
    move-result-object v1
    check-cast v1, Lcom/titan/ranger/bean/Media;
    if-eqz v1, :done

    invoke-virtual {v1}, Lcom/titan/ranger/bean/Media;->getName()Ljava/lang/String;
    move-result-object v0

    const-string/jumbo v2, "XUPER_VOD_FIX"
    const-string/jumbo v3, "Using first backend-provided VOD media"
    invoke-static {v2, v3}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I

    :done
    return-object v0
.end method'''
s2=s[:m.start()]+rep+s[m.end():]
open(p,'w',encoding='utf-8',newline='\n').write(s2)
print('PATCHED=1')
PY
cp "$I2" "$OUT/i2.after.smali"

echo 'Building APK...'
java -jar "$APKTOOL" b "$WORK/proj" -o "$WORK/unsigned.apk" > "$OUT/apktool-build.txt" 2>&1
"$ZIPALIGN" -f -p 4 "$WORK/unsigned.apk" "$WORK/aligned.apk"
keytool -genkeypair -noprompt -keystore "$WORK/test.jks" -storepass android -keypass android -alias patch -dname 'CN=XuperVODFix,O=LocalTest,C=MX' -keyalg RSA -keysize 2048 -validity 10000 >/dev/null 2>&1
CANDIDATE="$OUT/Xuper-6.2.4-VOD-FirstMedia-Tested.apk"
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
