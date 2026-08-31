#!/usr/bin/env bash
set -euo pipefail

OUT='diagnostics-vod-media-fallback'
WORK='/tmp/xuper-vod-direct'
BASE='xuper-stable.apk'
rm -rf "$OUT" "$WORK" "$BASE"
mkdir -p "$OUT" "$WORK/base" "$WORK/runtime" "$WORK/smali-full" "$WORK/stub/com/secneo/apkwrapper"
checksum() { sha256sum "$1"; }
: "${GH_TOKEN:?GH_TOKEN required}"

BASE_ARTIFACT_ID='9623417943'
BASE_SHA='8ba6eb4a13bdec2d8d8ab06a1502194f488ce58d9fb6de7feeb1c539ef0f7b4e'
curl -fL --retry 4 --retry-all-errors -H "Authorization: Bearer ${GH_TOKEN}" -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28' "https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/artifacts/${BASE_ARTIFACT_ID}/zip" -o "$WORK/base.zip"
unzip -q "$WORK/base.zip" -d "$WORK/base"
BASE_SRC=''
while IFS= read -r f; do if [ "$(checksum "$f" | awk '{print $1}')" = "$BASE_SHA" ]; then BASE_SRC="$f"; break; fi; done < <(find "$WORK/base" -type f -name '*.apk')
test -n "$BASE_SRC"; cp "$BASE_SRC" "$BASE"; checksum "$BASE" | tee "$OUT/base-sha256.txt"

RUNTIME_ARTIFACT_ID='9635194139'
curl -fL --retry 4 --retry-all-errors -H "Authorization: Bearer ${GH_TOKEN}" -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28' "https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/artifacts/${RUNTIME_ARTIFACT_ID}/zip" -o "$WORK/runtime.zip"
unzip -p "$WORK/runtime.zip" 'dex-all/runtime-018-3940f5414259.dex' > "$WORK/runtime18.dex"
unzip -p "$WORK/runtime.zip" 'dex-all/runtime-019-5d2a62ef889d.dex' > "$WORK/runtime19.dex"
test -s "$WORK/runtime18.dex"; test -s "$WORK/runtime19.dex"
checksum "$WORK/runtime18.dex" | tee "$OUT/runtime18-sha256.txt"; checksum "$WORK/runtime19.dex" | tee "$OUT/runtime19-sha256.txt"

SMALI_JAR="$WORK/smali-fat.jar"; BAKSMALI_JAR="$WORK/baksmali-fat.jar"
curl -fL --retry 3 --retry-all-errors 'https://github.com/baksmali/smali/releases/download/3.0.9/smali-3.0.9-fat.jar' -o "$SMALI_JAR"
curl -fL --retry 3 --retry-all-errors 'https://github.com/baksmali/smali/releases/download/3.0.9/baksmali-3.0.9-fat.jar' -o "$BAKSMALI_JAR"
java -jar "$BAKSMALI_JAR" disassemble "$WORK/runtime19.dex" -o "$WORK/smali-full" > "$OUT/baksmali-disassemble.txt" 2>&1
TARGET="$WORK/smali-full/m6/g2\$u.smali"; test -s "$TARGET"; cp "$TARGET" "$OUT/g2-u-original.smali"
test -s tools/patches/g2_u_vod_fallback.smali
cp tools/patches/g2_u_vod_fallback.smali "$TARGET"
cp "$TARGET" "$OUT/g2-u-patched.smali"
grep -F 'STATIC_VOD_FALLBACK' "$TARGET"
java -jar "$SMALI_JAR" assemble "$WORK/smali-full" -o "$WORK/classes2.dex" > "$OUT/smali-assemble.txt" 2>&1; test -s "$WORK/classes2.dex"

cat > "$WORK/stub/com/secneo/apkwrapper/AW.smali" <<'EOF'
.class public Lcom/secneo/apkwrapper/AW;
.super Landroid/app/Application;
.source "AW.java"
.method public constructor <init>()V
    .locals 0
    invoke-direct {p0}, Landroid/app/Application;-><init>()V
    return-void
.end method
EOF
cat > "$WORK/stub/com/secneo/apkwrapper/AP.smali" <<'EOF'
.class public Lcom/secneo/apkwrapper/AP;
.super Landroid/app/AppComponentFactory;
.source "AP.java"
.method public constructor <init>()V
    .locals 0
    invoke-direct {p0}, Landroid/app/AppComponentFactory;-><init>()V
    return-void
.end method
EOF
cat > "$WORK/stub/com/secneo/apkwrapper/CP.smali" <<'EOF'
.class public Lcom/secneo/apkwrapper/CP;
.super Landroid/content/ContentProvider;
.source "CP.java"

.method public constructor <init>()V
    .locals 0
    invoke-direct {p0}, Landroid/content/ContentProvider;-><init>()V
    return-void
.end method

.method public onCreate()Z
    .locals 1
    const/4 v0, 0x1
    return v0
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

.method public query(Landroid/net/Uri;[Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;Ljava/lang/String;)Landroid/database/Cursor;
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
EOF
java -jar "$SMALI_JAR" assemble "$WORK/stub" -o "$WORK/classes3.dex" > "$OUT/stub-assemble.txt" 2>&1; test -s "$WORK/classes3.dex"

cp "$BASE" "$WORK/unsigned.apk"
zip -q -d "$WORK/unsigned.apk" 'META-INF/*.RSA' 'META-INF/*.DSA' 'META-INF/*.EC' 'META-INF/*.SF' 'META-INF/MANIFEST.MF' 'classes.dex' 'classes2.dex' 'classes3.dex' >/dev/null 2>&1 || true
cp "$WORK/runtime18.dex" "$WORK/classes.dex"; (cd "$WORK" && zip -q -u unsigned.apk classes.dex classes2.dex classes3.dex)
KEYSTORE="$WORK/test.jks"; keytool -genkeypair -noprompt -keystore "$KEYSTORE" -storepass android -keypass android -alias androiddebugkey -dname 'CN=Xuper Direct Runtime,O=Android,C=MX' -keyalg RSA -keysize 2048 -validity 10000 >/dev/null 2>&1
APKSIGNER="$(command -v apksigner)"; ZIPALIGN="$(command -v zipalign)"; "$ZIPALIGN" -f 4 "$WORK/unsigned.apk" "$WORK/aligned.apk"
CANDIDATE="$OUT/Xuper-6.2.4-VOD-StaticFallback-NoFrida.apk"; "$APKSIGNER" sign --ks "$KEYSTORE" --ks-pass pass:android --key-pass pass:android --ks-key-alias androiddebugkey --out "$CANDIDATE" "$WORK/aligned.apk"
"$APKSIGNER" verify --verbose --print-certs "$CANDIDATE" > "$OUT/signing.txt"; checksum "$CANDIDATE" | tee "$OUT/candidate-sha256.txt"
unzip -l "$CANDIDATE" > "$OUT/package-files.txt"; unzip -p "$CANDIDATE" classes.dex > "$OUT/classes1-final.dex"; unzip -p "$CANDIDATE" classes2.dex > "$OUT/classes2-final.dex"; unzip -p "$CANDIDATE" classes3.dex > "$OUT/classes3-final.dex"
echo 'DIRECT_RUNTIME_DEPROTECTED_VOD_FALLBACK_BUILD_OK' | tee "$OUT/build-result.txt"
