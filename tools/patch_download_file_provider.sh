#!/usr/bin/env bash
set -euo pipefail
APK="${1:-diagnostics-vod-media-fallback/Xuper-6.2.4-VOD-StaticFallback-NoFrida.apk}"
WORK='/tmp/xuper-vod-direct'; PATCH="$WORK/download-provider-patch"
SMALI_JAR="$WORK/smali-fat.jar"; BAKSMALI_JAR="$WORK/baksmali-fat.jar"; KEYSTORE="$WORK/test.jks"
for f in "$APK" "$SMALI_JAR" "$BAKSMALI_JAR" "$KEYSTORE"; do test -s "$f"; done
rm -rf "$PATCH"; mkdir -p "$PATCH/smali/com/mobile/provider" "$PATCH/smali/androidx/startup" "$PATCH/smali/io/appmetrica/analytics/internal"
unzip -p "$APK" classes.dex > "$PATCH/classes.dex"
java -jar "$BAKSMALI_JAR" disassemble "$PATCH/classes.dex" -o "$PATCH/smali"
cat > "$PATCH/smali/com/mobile/provider/DownloadFileProvider.smali" <<'EOF'
.class public Lcom/mobile/provider/DownloadFileProvider;
.super Landroidx/core/content/FileProvider;
.method public constructor <init>()V
 .locals 0
 invoke-direct {p0}, Landroidx/core/content/FileProvider;-><init>()V
 return-void
.end method
EOF
for cls in androidx/startup/InitializationProvider io/appmetrica/analytics/internal/PreloadInfoContentProvider; do
  mkdir -p "$PATCH/smali/$(dirname "$cls")"
  cat > "$PATCH/smali/$cls.smali" <<EOF
.class public L${cls};
.super Landroid/content/ContentProvider;
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
done
java -jar "$SMALI_JAR" assemble "$PATCH/smali" -o "$PATCH/classes.dex.new"
cp "$APK" "$PATCH/unsigned.apk"
zip -q -d "$PATCH/unsigned.apk" 'META-INF/*.RSA' 'META-INF/*.DSA' 'META-INF/*.EC' 'META-INF/*.SF' 'META-INF/MANIFEST.MF' classes.dex >/dev/null 2>&1 || true
cp "$PATCH/classes.dex.new" "$PATCH/classes.dex"; (cd "$PATCH" && zip -q -u unsigned.apk classes.dex)
zipalign -f 4 "$PATCH/unsigned.apk" "$PATCH/aligned.apk"
apksigner sign --ks "$KEYSTORE" --ks-pass pass:android --key-pass pass:android --ks-key-alias androiddebugkey --out "$PATCH/signed.apk" "$PATCH/aligned.apk"
apksigner verify --verbose "$PATCH/signed.apk" >/dev/null
cp "$PATCH/signed.apk" "$APK"
echo 'MANIFEST_PROVIDER_PRIMARY_DEX_STUBS_OK'; sha256sum "$APK"
