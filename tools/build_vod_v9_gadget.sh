#!/usr/bin/env bash
set -euo pipefail

PKG='com.msandroid.mobile'
FRIDA_VERSION='17.2.17'
BASE='xuper-base.apk'
OUT='diagnostics-vod-v9-gadget'
WORK='/tmp/xuper-vod-v9'
rm -rf "$OUT" "$WORK"
mkdir -p "$OUT" "$WORK"

checksum() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1"
  else
    shasum -a 256 "$1"
  fi
}

: "${GH_TOKEN:?GH_TOKEN required}"
ARTIFACT_ID='9623417943'
curl -fL --retry 4 --retry-all-errors -H "Authorization: Bearer ${GH_TOKEN}" -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28' "https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/artifacts/${ARTIFACT_ID}/zip" -o "$WORK/base.zip"
unzip -q "$WORK/base.zip" -d "$WORK/base-artifact"
BASE_SRC=$(find "$WORK/base-artifact" -type f -name '*.apk' | head -1)
test -n "$BASE_SRC"
cp "$BASE_SRC" "$BASE"
checksum "$BASE" | tee "$OUT/base-sha256.txt"

curl -fL --retry 3 --retry-all-errors 'https://github.com/iBotPeaches/Apktool/releases/download/v2.11.1/apktool_2.11.1.jar' -o "$WORK/apktool.jar"
java -jar "$WORK/apktool.jar" d -f "$BASE" -o "$WORK/decoded" >/dev/null

SMALI="$WORK/decoded/smali/com/xuper/vodfix"
mkdir -p "$SMALI"
cat > "$SMALI/VodFixProvider.smali" <<'SMALI'
.class public Lcom/xuper/vodfix/VodFixProvider;
.super Landroid/content/ContentProvider;
.source "VodFixProvider.java"
.method public constructor <init>()V
    .locals 0
    invoke-direct {p0}, Landroid/content/ContentProvider;-><init>()V
    return-void
.end method
.method public onCreate()Z
    .locals 4
    :try_start
    new-instance v0, Landroid/os/Handler;
    invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
    move-result-object v1
    invoke-direct {v0, v1}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V
    new-instance v1, Lcom/xuper/vodfix/VodFixProvider$1;
    invoke-direct {v1}, Lcom/xuper/vodfix/VodFixProvider$1;-><init>()V
    const-wide/16 v2, 0x1f40
    invoke-virtual {v0, v1, v2, v3}, Landroid/os/Handler;->postDelayed(Ljava/lang/Runnable;J)Z
    :try_end
    .catch Ljava/lang/Throwable; {:try_start .. :try_end} :catch_all
    :catch_all
    const/4 v0, 0x1
    return v0
.end method
.method public query(Landroid/net/Uri;[Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;Ljava/lang/String;)Landroid/database/Cursor;
    .locals 1
    const/4 v0, 0x0
    return-object v0
.end method
.method public getType(Landroid/net/Uri;)Ljava/lang/String;
    .locals 1
    const/4 v0, 0x0
    return-object v0
.end method
.method public insert(Landroid/net/Uri;Landroid/content/ContentValues;)Landroid/net/Uri;
    .locals 1
    const/4 v0, 0x0
    return-object v0
.end method
.method public delete(Landroid/net/Uri;Ljava/lang/String;[Ljava/lang/String;)I
    .locals 1
    const/4 v0, 0x0
    return v0
.end method
.method public update(Landroid/net/Uri;Landroid/content/ContentValues;Ljava/lang/String;[Ljava/lang/String;)I
    .locals 1
    const/4 v0, 0x0
    return v0
.end method
SMALI
cat > "$SMALI/VodFixProvider\$1.smali" <<'SMALI'
.class final Lcom/xuper/vodfix/VodFixProvider$1;
.super Ljava/lang/Object;
.implements Ljava/lang/Runnable;
.source "VodFixProvider.java"
.method public constructor <init>()V
    .locals 0
    invoke-direct {p0}, Ljava/lang/Object;-><init>()V
    return-void
.end method
.method public run()V
    .locals 1
    :try_start
    const-string v0, "gadget"
    invoke-static {v0}, Ljava/lang/System;->loadLibrary(Ljava/lang/String;)V
    :try_end
    .catch Ljava/lang/Throwable; {:try_start .. :try_end} :catch_all
    :catch_all
    return-void
.end method
SMALI
python3 - "$WORK/decoded/AndroidManifest.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
p=sys.argv[1]; ET.register_namespace('android','http://schemas.android.com/apk/res/android'); ns='{http://schemas.android.com/apk/res/android}'
t=ET.parse(p); r=t.getroot(); app=r.find('application')
for x in list(app.findall('provider')):
    if x.get(ns+'name')=='com.xuper.vodfix.VodFixProvider': app.remove(x)
e=ET.SubElement(app,'provider'); e.set(ns+'name','com.xuper.vodfix.VodFixProvider'); e.set(ns+'authorities','com.msandroid.mobile.vodfix'); e.set(ns+'exported','false'); e.set(ns+'initOrder','999999')
t.write(p,encoding='utf-8',xml_declaration=True)
PY
for spec in 'arm64-v8a:arm64' 'armeabi-v7a:arm'; do
  abi=${spec%%:*}; frida_arch=${spec##*:}; d="$WORK/decoded/lib/$abi"; mkdir -p "$d"
  curl -fL --retry 3 --retry-all-errors "https://github.com/frida/frida/releases/download/${FRIDA_VERSION}/frida-gadget-${FRIDA_VERSION}-android-${frida_arch}.so.xz" -o "$WORK/gadget-${abi}.xz"
  xz -dc "$WORK/gadget-${abi}.xz" > "$d/libgadget.so"
  cat > "$d/libgadget.config.so" <<'CFG'
{"interaction":{"type":"script","path":"libgadget.script.so","on_change":"ignore"},"runtime":"qjs","teardown":"minimal"}
CFG
  cat > "$d/libgadget.script.so" <<'JS'
'use strict';
(function(){var installed=false;function attempt(){if(installed||!Java.available)return;Java.perform(function(){try{var Z=Java.use('cb.z1');var g=Z.g.overload('java.lang.Object','java.lang.String','boolean','java.lang.Class','java.lang.String','java.util.HashMap','java.lang.String','boolean');g.implementation=function(body,uri,secure,responseClass,method,headers,serviceName,flag){var u=uri?uri.toString():'';if(u.indexOf('api/portalCore/v10/startPlayVOD')!==-1){var patched=u.replace('api/portalCore/v10/startPlayVOD','api/portalCore/v9/startPlayVOD');console.log('[XUPER_VOD_FIX] route '+u+' -> '+patched);return g.call(this,body,patched,secure,responseClass,method,headers,serviceName,flag);}return g.call(this,body,uri,secure,responseClass,method,headers,serviceName,flag);};installed=true;console.log('[XUPER_VOD_FIX] cb.z1.g hook installed');}catch(e){}});}setInterval(attempt,500);attempt();})();
JS
done
java -jar "$WORK/apktool.jar" b "$WORK/decoded" -o "$WORK/unsigned.apk" >/dev/null
KEYSTORE="$WORK/test.jks"
keytool -genkeypair -noprompt -keystore "$KEYSTORE" -storepass android -keypass android -alias androiddebugkey -dname 'CN=Android Debug,O=Android,C=US' -keyalg RSA -keysize 2048 -validity 10000 >/dev/null 2>&1
APKSIGNER=$(find "$ANDROID_HOME/build-tools" -type f -name apksigner | sort -V | tail -1)
ZIPALIGN=$(find "$ANDROID_HOME/build-tools" -type f -name zipalign | sort -V | tail -1)
"$ZIPALIGN" -f 4 "$WORK/unsigned.apk" "$WORK/aligned.apk"
"$APKSIGNER" sign --ks "$KEYSTORE" --ks-pass pass:android --key-pass pass:android --ks-key-alias androiddebugkey --out "$OUT/Xuper-VOD-v9-Gadget-Candidate.apk" "$WORK/aligned.apk"
"$APKSIGNER" verify --verbose --print-certs "$OUT/Xuper-VOD-v9-Gadget-Candidate.apk" > "$OUT/signing.txt"
checksum "$OUT/Xuper-VOD-v9-Gadget-Candidate.apk" | tee "$OUT/candidate-sha256.txt"
echo 'BUILD_OK' | tee "$OUT/build-result.txt"
