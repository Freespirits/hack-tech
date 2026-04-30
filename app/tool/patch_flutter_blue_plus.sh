#!/usr/bin/env bash
# Patch flutter_blue_plus_android <= 7.0.4 for compatibility with
# AGP 8.x + Gradle 8.x.
#
# Background: the plugin's android/build.gradle uses
#     compileSdkVersion = flutter.compileSdkVersion
# which fails under AGP 8.x with "Cannot invoke method substring() on
# null object". Upstream tracks this; until a fix lands we substitute
# a literal `compileSdk 34`.
#
# Idempotent — running this multiple times produces the same file.

set -euo pipefail

PUB_CACHE="${PUB_CACHE:-$HOME/.pub-cache}"
PLUGIN_GLOB="$PUB_CACHE/hosted/pub.dev/flutter_blue_plus_android-*/android/build.gradle"

shopt -s nullglob
matched=()
for f in $PLUGIN_GLOB; do
  matched+=("$f")
done

if [ ${#matched[@]} -eq 0 ]; then
  echo "patch_flutter_blue_plus.sh: no flutter_blue_plus_android plugin found at"
  echo "  $PLUGIN_GLOB"
  echo "Run 'flutter pub get' first."
  exit 1
fi

for f in "${matched[@]}"; do
  if grep -q "compileSdkVersion = flutter.compileSdkVersion" "$f"; then
    sed -i 's|compileSdkVersion = flutter.compileSdkVersion|compileSdk 34|' "$f"
    echo "patched: $f"
  else
    echo "already patched: $f"
  fi
done
