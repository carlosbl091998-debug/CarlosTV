#!/usr/bin/env bash
set -euo pipefail
APK="${1:-diagnostics-vod-media-fallback/Xuper-6.2.4-VOD-StaticFallback-NoFrida.apk}"
WORK='/tmp/xuper-vod-direct'; PATCH="$WORK/firebase-provider-patch"
SMALI_JAR="$WORK/smali-fat.jar"; BAKSMALI_JAR="$WORK/baksmali-fat.jar"; KEYSTORE="$WORK/test.jks"
for f in "$APK" "$SMALI_JAR" "$BAKSMALI_JAR" "$KEYSTORE"; do test -s "$f"; done
rm -rf "$PATCH"; mkdir -p "$PATCH/smali/com/google/firebase/provider"
unzip -p "$APK" classes.dex > "$PATCH/classes.dex"
java -jar "$BAKSMALI_JAR" disassemble "$PATCH/classes.dex" -o "$PATCH/smali"
cat > "$PATCH/smali/com/google/firebase/provider/FirebaseInitProvider.smali" <<'EOF'
.class public Lcom/google/firebase/provider/FirebaseInitProvider;
.super Landroid/content/ContentProvider;
.source "FirebaseInitProvider.java"
.method public constructor <init>()V
    .locals 0
    invoke-direct {p0}, Landroid/content/ContentProvider;-><init>()V
    return-void
.end method
.method public onCreate()Z
    .locals 2
    invoke-virtual {p0}, Lcom/google/firebase/provider/FirebaseInitProvider;->getContext()Landroid/content/Context;
    move-result-object v0
    if-eqz v0, :done
    invoke-static {v0}, Lcom/google/firebase/FirebaseApp;->initializeApp(Landroid/content/Context;)Lcom/google/firebase/FirebaseApp;
    move-result-object v1
:done
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
java -jar "$SMALI_JAR" assemble "$PATCH/smali" -o "$PATCH/classes.dex.new"
cp "$APK" "$PATCH/unsigned.apk"
zip -q -d "$PATCH/unsigned.apk" 'META-INF/*.RSA' 'META-INF/*.DSA' 'META-INF/*.EC' 'META-INF/*.SF' 'META-INF/MANIFEST.MF' classes.dex >/dev/null 2>&1 || true
cp "$PATCH/classes.dex.new" "$PATCH/classes.dex"; (cd "$PATCH" && zip -q -u unsigned.apk classes.dex)
zipalign -f 4 "$PATCH/unsigned.apk" "$PATCH/aligned.apk"
apksigner sign --ks "$KEYSTORE" --ks-pass pass:android --key-pass pass:android --ks-key-alias androiddebugkey --out "$PATCH/signed.apk" "$PATCH/aligned.apk"
apksigner verify --verbose "$PATCH/signed.apk" >/dev/null
cp "$PATCH/signed.apk" "$APK"
echo 'FIREBASE_INIT_PROVIDER_REAL_INIT_OK'; sha256sum "$APK"
