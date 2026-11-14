#!/usr/bin/env bash
# Release APKs, one per CPU type (a single "universal" APK would carry
# yt-dlp's Python/FFmpeg for every CPU: ~2x the size).
#   app-arm64-v8a-release.apk    — almost every phone from 2017 on
#   app-armeabi-v7a-release.apk  — older / low-end 32-bit phones
# --obfuscate + --split-debug-info: ~20% smaller Dart code. Keep build/symbols
# from each release to read crash stack traces:
#   flutter symbolize -i <trace.txt> -d build/symbols/app.android-arm64.symbols
# yt-dlp's bundled archives are trimmed during the Gradle build
# (tool/trim_ytdlp_bundles.py, needs python3).
set -euo pipefail
cd "$(dirname "$0")/.."
flutter build apk --release --split-per-abi \
  --target-platform android-arm,android-arm64 \
  --obfuscate --split-debug-info=build/symbols \
  --dart-define=TOOMU_BUILD="build $(date '+%m-%d %H:%M')"
for apk in build/app/outputs/flutter-apk/app-*-release.apk; do
  printf '%6.1f MB  %s\n' "$(echo "$(stat -f%z "$apk" 2>/dev/null || stat -c%s "$apk") / 1048576" | bc -l)" "$apk"
done
