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

.field private static startupTime:Lcom/google/firebase/StartupTime;
.field private static currentlyInitializing:Ljava/util/concurrent/atomic/AtomicBoolean;

.method static constructor <clinit>()V
    .locals 1
    invoke-static {}, Lcom/google/firebase/StartupTime;->now()Lcom/google/firebase/StartupTime;
    move-result-object v0
    sput-object v0, Lcom/google/firebase/provider/FirebaseInitProvider;->startupTime:Lcom/google/firebase/StartupTime;
    new-instance v0, Ljava/util/concurrent/atomic/AtomicBoolean;
    invoke-direct {v0}, Ljava/util/concurrent/atomic/AtomicBoolean;-><init>()V
    sput-object v0, Lcom/google/firebase/provider/FirebaseInitProvider;->currentlyInitializing:Ljava/util/concurrent/atomic/AtomicBoolean;
    return-void
.end method

.method public constructor <init>()V
    .locals 0
    invoke-direct {p0}, Landroid/content/ContentProvider;-><init>()V
    return-void
.end method

.method public static getStartupTime()Lcom/google/firebase/StartupTime;
    .locals 1
    sget-object v0, Lcom/google/firebase/provider/FirebaseInitProvider;->startupTime:Lcom/google/firebase/StartupTime;
    return-object v0
.end method

.method public static isCurrentlyInitializing()Z
    .locals 1
    sget-object v0, Lcom/google/firebase/provider/FirebaseInitProvider;->currentlyInitializing:Ljava/util/concurrent/atomic/AtomicBoolean;
    invoke-virtual {v0}, Ljava/util/concurrent/atomic/AtomicBoolean;->get()Z
    move-result v0
    return v0
.end method

.method public onCreate()Z
    .locals 3
    sget-object v0, Lcom/google/firebase/provider/FirebaseInitProvider;->currentlyInitializing:Ljava/util/concurrent/atomic/AtomicBoolean;
    const/4 v1, 0x1
    invoke-virtual {v0, v1}, Ljava/util/concurrent/atomic/AtomicBoolean;->set(Z)V
    :try_start
    invoke-virtual {p0}, Lcom/google/firebase/provider/FirebaseInitProvider;->getContext()Landroid/content/Context;
    move-result-object v0
    if-eqz v0, :done
    invoke-static {v0}, Lcom/google/firebase/FirebaseApp;->initializeApp(Landroid/content/Context;)Lcom/google/firebase/FirebaseApp;
    move-result-object v2
    :done
    sget-object v0, Lcom/google/firebase/provider/FirebaseInitProvider;->currentlyInitializing:Ljava/util/concurrent/atomic/AtomicBoolean;
    const/4 v1, 0x0
    invoke-virtual {v0, v1}, Ljava/util/concurrent/atomic/AtomicBoolean;->set(Z)V
    const/4 v0, 0x0
    return v0
    :try_end
    .catchall {:try_start .. :try_end} :catchall
    :catchall
    move-exception v2
    sget-object v0, Lcom/google/firebase/provider/FirebaseInitProvider;->currentlyInitializing:Ljava/util/concurrent/atomic/AtomicBoolean;
    const/4 v1, 0x0
    invoke-virtual {v0, v1}, Ljava/util/concurrent/atomic/AtomicBoolean;->set(Z)V
    throw v2
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
echo 'FIREBASE_INIT_PROVIDER_REAL_API_OK'; sha256sum "$APK"
