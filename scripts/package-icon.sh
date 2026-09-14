#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Mechanical size/format conversion only. The artwork is imagegen's original PNG.
ICONSET="$PWD/build/Voxen.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" VoiceIntentRouter/Resources/voxen-logo-v1.png \
    --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" VoiceIntentRouter/Resources/voxen-logo-v1.png \
    --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o VoiceIntentRouter/Resources/Voxen.icns
