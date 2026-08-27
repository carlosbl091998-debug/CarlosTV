#!/usr/bin/env bash
set -euo pipefail

PKG='com.msandroid.mobile'
BASE_OUT='diagnostics-vod-v9-gadget/Xuper-VOD-v9-Gadget-Candidate.apk'
OUT='diagnostics-vod-media-fallback'
WORK='/tmp/xuper-vod-media-fallback'
rm -rf "$OUT" "$WORK"
mkdir -p "$OUT" "$WORK"

# Reuse the proven early Frida-Gadget injection against the validated stable APK.
bash tools/build_vod_v9_gadget.sh
cp "$BASE_OUT" "$WORK/gadget-base.apk"

APKTOOL="$WORK/apktool.jar"
curl -fL --retry 3 --retry-all-errors \
  'https://github.com/iBotPeaches/Apktool/releases/download/v2.11.1/apktool_2.11.1.jar' \
  -o "$APKTOOL"
java -jar "$APKTOOL" d -f "$WORK/gadget-base.apk" -o "$WORK/decoded" > "$OUT/decode.txt" 2>&1

# Replace the previous experimental endpoint hook with a patch at the exact
# runtime mapper that converts StartPlayVODResult.totalMovieList into the
# canonical 480p/720p/1080p map consumed by the player.
cat > "$WORK/vod-media-fallback.js" <<'JS'
'use strict';
(function () {
  var installed = false;
  var attempts = 0;

  function log(s) {
    console.log('[XUPER_VOD_MEDIA] ' + s);
  }

  function attempt() {
    if (installed || !Java.available) return;
    Java.perform(function () {
      attempts++;
      try {
        var Mapper = Java.use('m6.g2$u');
        var typed = Mapper.invoke.overload('mobile.com.requestframe.utils.response.StartPlayVODResult');

        typed.implementation = function (result) {
          var out = typed.call(this, result);
          try {
            var data = result ? result.getData() : null;
            var eps = data ? data.getEpisodeList() : null;
            if (eps === null || eps.isEmpty()) {
              log('EMPTY_EPISODE_LIST');
              return out;
            }

            var episode0 = eps.get(0);
            var totals = episode0 ? episode0.getTotalMovieList() : null;
            if (totals === null || totals.isEmpty()) {
              log('EMPTY_TOTAL_MOVIE_LIST');
              return out;
            }

            log('episodeList=' + eps.size() + ' totalMovieList=' + totals.size() + ' mapperOut=' + out.size());
            var firstPlayable = null;
            for (var i = 0; i < totals.size(); i++) {
              var item = totals.get(i);
              if (item === null) continue;
              var q = item.getQuality();
              var movies = item.getMovieList();
              var count = movies === null ? -1 : movies.size();
              log('source[' + i + '] quality=' + q + ' movieList=' + count);
              if (firstPlayable === null && movies !== null && !movies.isEmpty()) {
                firstPlayable = item;
              }
            }

            if (out !== null && out.isEmpty() && firstPlayable !== null) {
              // The original 6.2.4 code accepts only exact labels 480p/720p/1080p.
              // Newer backend labels can therefore leave the map empty even though
              // a usable movieList exists. Expose the same backend source under the
              // three canonical keys so downstream quality-selection code remains intact.
              out.put('480p', firstPlayable);
              out.put('720p', firstPlayable);
              out.put('1080p', firstPlayable);
              log('PATCH_APPLIED canonical fallback map size=' + out.size() +
                  ' actualQuality=' + firstPlayable.getQuality());
            } else if (out !== null && !out.isEmpty()) {
              log('ORIGINAL_MAP_OK size=' + out.size());
            } else {
              log('NO_PLAYABLE_MOVIE_LIST');
            }
          } catch (e) {
            log('RUNTIME_DIAG_ERROR ' + e);
          }
          return out;
        };

        installed = true;
        log('HOOK_INSTALLED m6.g2$u.invoke(StartPlayVODResult) attempts=' + attempts);
      } catch (e) {
        if ((attempts % 20) === 0) log('WAITING_FOR_PROTECTED_DEX attempts=' + attempts + ' err=' + e);
      }
    });
  }

  setInterval(attempt, 500);
  attempt();
})();
JS

for abi in arm64-v8a armeabi-v7a; do
  target="$WORK/decoded/lib/$abi/libgadget.script.so"
  test -f "$target"
  cp "$WORK/vod-media-fallback.js" "$target"
done

java -jar "$APKTOOL" b "$WORK/decoded" -o "$WORK/unsigned.apk" > "$OUT/build.txt" 2>&1

KEYSTORE="$WORK/test.jks"
keytool -genkeypair -noprompt -keystore "$KEYSTORE" -storepass android -keypass android \
  -alias androiddebugkey -dname 'CN=Xuper VOD Media Fallback,O=Android,C=MX' \
  -keyalg RSA -keysize 2048 -validity 10000 >/dev/null 2>&1
APKSIGNER=$(find "$ANDROID_HOME/build-tools" -type f -name apksigner | sort -V | tail -1)
ZIPALIGN=$(find "$ANDROID_HOME/build-tools" -type f -name zipalign | sort -V | tail -1)
"$ZIPALIGN" -f 4 "$WORK/unsigned.apk" "$WORK/aligned.apk"
CANDIDATE="$OUT/Xuper-6.2.4-VOD-MediaFallback-Test.apk"
"$APKSIGNER" sign --ks "$KEYSTORE" --ks-pass pass:android --key-pass pass:android \
  --ks-key-alias androiddebugkey --out "$CANDIDATE" "$WORK/aligned.apk"
"$APKSIGNER" verify --verbose --print-certs "$CANDIDATE" > "$OUT/signing.txt"
sha256sum "$CANDIDATE" | tee "$OUT/candidate-sha256.txt"

# Confirm the injected diagnostic/patch payload is actually present in both ABIs.
for abi in arm64-v8a armeabi-v7a; do
  unzip -p "$CANDIDATE" "lib/$abi/libgadget.script.so" | \
    grep -q 'HOOK_INSTALLED m6.g2\$u.invoke(StartPlayVODResult)'
done

echo 'BUILD_OK' | tee "$OUT/build-result.txt"
