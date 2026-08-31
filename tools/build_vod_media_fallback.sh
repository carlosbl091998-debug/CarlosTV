#!/usr/bin/env bash
set -euo pipefail

OUT='diagnostics-vod-media-fallback'
WORK='/tmp/xuper-vod-direct'
BASE='xuper-stable.apk'
rm -rf "$OUT" "$WORK" "$BASE"
mkdir -p "$OUT" "$WORK/base" "$WORK/runtime" "$WORK/smali-full" "$WORK/stub/com/secneo/apkwrapper" "$WORK/stub/com/google/firebase/provider" "$WORK/primary-smali" "$WORK/dummy23"
checksum() { sha256sum "$1"; }
: "${GH_TOKEN:?GH_TOKEN required}"

BASE_ARTIFACT_ID='9623417943'
BASE_SHA='8ba6eb4a13bdec2d8d8ab06a1502194f488ce58d9fb6de7feeb1c539ef0f7b4e'
curl -fL --retry 4 --retry-all-errors -H "Authorization: Bearer ${GH_TOKEN}" -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28' "https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/artifacts/${BASE_ARTIFACT_ID}/zip" -o "$WORK/base.zip"
unzip -q "$WORK/base.zip" -d "$WORK/base"
BASE_SRC=''
while IFS= read -r f; do
  if [ "$(checksum "$f" | awk '{print $1}')" = "$BASE_SHA" ]; then BASE_SRC="$f"; break; fi
done < <(find "$WORK/base" -type f -name '*.apk')
test -n "$BASE_SRC"
cp "$BASE_SRC" "$BASE"
checksum "$BASE" | tee "$OUT/base-sha256.txt"

RUNTIME_ARTIFACT_ID='9635194139'
curl -fL --retry 4 --retry-all-errors -H "Authorization: Bearer ${GH_TOKEN}" -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28' "https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/artifacts/${RUNTIME_ARTIFACT_ID}/zip" -o "$WORK/runtime.zip"
for i in $(seq 1 68); do
  if [ "$i" -eq 23 ] || [ "$i" -eq 19 ]; then continue; fi
  tag=$(printf '%03d' "$i")
  entry=$(unzip -Z1 "$WORK/runtime.zip" | grep -E "^dex-all/runtime-${tag}-[^/]+[.]dex$" | head -1)
  test -n "$entry"
  if [ "$i" -eq 1 ]; then outdex="$WORK/classes.dex"; else outdex="$WORK/classes${i}.dex"; fi
  unzip -p "$WORK/runtime.zip" "$entry" > "$outdex"
  test -s "$outdex"
done

entry19=$(unzip -Z1 "$WORK/runtime.zip" | grep -E '^dex-all/runtime-019-[^/]+[.]dex$' | head -1)
test -n "$entry19"
unzip -p "$WORK/runtime.zip" "$entry19" > "$WORK/runtime19.dex"
test -s "$WORK/runtime19.dex"
checksum "$WORK/runtime19.dex" | tee "$OUT/runtime19-sha256.txt"

SMALI_JAR="$WORK/smali-fat.jar"
BAKSMALI_JAR="$WORK/baksmali-fat.jar"
curl -fL --retry 3 --retry-all-errors 'https://github.com/baksmali/smali/releases/download/3.0.9/smali-3.0.9-fat.jar' -o "$SMALI_JAR"
curl -fL --retry 3 --retry-all-errors 'https://github.com/baksmali/smali/releases/download/3.0.9/baksmali-3.0.9-fat.jar' -o "$BAKSMALI_JAR"

java -jar "$BAKSMALI_JAR" disassemble "$WORK/runtime19.dex" -o "$WORK/smali-full" > "$OUT/baksmali-disassemble.txt" 2>&1
TARGET="$WORK/smali-full/m6/g2\$u.smali"
test -s "$TARGET"
cp "$TARGET" "$OUT/g2-u-original.smali"
test -s tools/patches/g2_u_vod_fallback.smali
cp tools/patches/g2_u_vod_fallback.smali "$TARGET"
cp "$TARGET" "$OUT/g2-u-patched.smali"
grep -F 'STATIC_VOD_FALLBACK' "$TARGET"
java -jar "$SMALI_JAR" assemble "$WORK/smali-full" -o "$WORK/classes19.dex" > "$OUT/smali-assemble.txt" 2>&1
test -s "$WORK/classes19.dex"

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
cat > "$WORK/stub/com/google/firebase/provider/FirebaseInitProvider.smali" <<'EOF'
.class public Lcom/google/firebase/provider/FirebaseInitProvider;
.super Landroid/content/ContentProvider;
.source "FirebaseInitProvider.java"
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

# Android resolves Application/AppComponentFactory/providers before startup; put
# manifest compatibility classes in the primary DEX, not a secondary DEX.
java -jar "$BAKSMALI_JAR" disassemble "$WORK/classes.dex" -o "$WORK/primary-smali" > "$OUT/primary-disassemble.txt" 2>&1
mkdir -p "$WORK/primary-smali/com/secneo/apkwrapper" "$WORK/primary-smali/com/google/firebase/provider"
cp "$WORK/stub/com/secneo/apkwrapper/"*.smali "$WORK/primary-smali/com/secneo/apkwrapper/"
cp "$WORK/stub/com/google/firebase/provider/"*.smali "$WORK/primary-smali/com/google/firebase/provider/"
java -jar "$SMALI_JAR" assemble "$WORK/primary-smali" -o "$WORK/classes.dex.new" > "$OUT/primary-assemble.txt" 2>&1
mv "$WORK/classes.dex.new" "$WORK/classes.dex"

# Keep the recovered 68-slot class path contiguous without loading native SecNeo shell.
cat > "$WORK/dummy23/Placeholder.smali" <<'EOF'
.class public final Lxuper/compat/Dex23Placeholder;
.super Ljava/lang/Object;
.method private constructor <init>()V
    .locals 0
    invoke-direct {p0}, Ljava/lang/Object;-><init>()V
    return-void
.end method
EOF
java -jar "$SMALI_JAR" assemble "$WORK/dummy23" -o "$WORK/classes23.dex" > "$OUT/dummy23-assemble.txt" 2>&1
test -s "$WORK/classes23.dex"

printf '%s\n' "$WORK"/classes*.dex | sort -V > "$OUT/recovered-dex-files.txt"
test "$(wc -l < "$OUT/recovered-dex-files.txt")" -eq 68

cp "$BASE" "$WORK/unsigned.apk"
zip -q -d "$WORK/unsigned.apk" 'META-INF/*.RSA' 'META-INF/*.DSA' 'META-INF/*.EC' 'META-INF/*.SF' 'META-INF/MANIFEST.MF' 'classes*.dex' >/dev/null 2>&1 || true
(cd "$WORK" && zip -q -u unsigned.apk classes.dex classes{2..68}.dex)

KEYSTORE="$WORK/test.jks"
keytool -genkeypair -noprompt -keystore "$KEYSTORE" -storepass android -keypass android -alias androiddebugkey -dname 'CN=Xuper Direct Runtime,O=Android,C=MX' -keyalg RSA -keysize 2048 -validity 10000 >/dev/null 2>&1
APKSIGNER="$(command -v apksigner)"
ZIPALIGN="$(command -v zipalign)"
"$ZIPALIGN" -f 4 "$WORK/unsigned.apk" "$WORK/aligned.apk"
CANDIDATE="$OUT/Xuper-6.2.4-VOD-StaticFallback-NoFrida.apk"
"$APKSIGNER" sign --ks "$KEYSTORE" --ks-pass pass:android --key-pass pass:android --ks-key-alias androiddebugkey --out "$CANDIDATE" "$WORK/aligned.apk"
"$APKSIGNER" verify --verbose --print-certs "$CANDIDATE" > "$OUT/signing.txt"
checksum "$CANDIDATE" | tee "$OUT/candidate-sha256.txt"
unzip -l "$CANDIDATE" > "$OUT/package-files.txt"
echo 'FULL_68_DEX_PRIMARY_STUBS_FIREBASE_VOD_FALLBACK_BUILD_OK' | tee "$OUT/build-result.txt"
