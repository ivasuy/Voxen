#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR="$PWD/build"
APP_DIR="$BUILD_DIR/Voxen.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$BUILD_DIR/module-cache"
SWIFT_FLAGS=()
if [[ "${VOXEN_STRICT_CONCURRENCY:-0}" == "1" ]]; then
  SWIFT_FLAGS=(-strict-concurrency=complete -warnings-as-errors)
fi
SOURCES=()
while IFS= read -r file; do SOURCES+=("$file"); done < <(find Voxen -name '*.swift' -print | sort)
xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 \
  -module-cache-path "$BUILD_DIR/module-cache" -O -parse-as-library \
  "${SWIFT_FLAGS[@]}" "${SOURCES[@]}" -o "$APP_DIR/Contents/MacOS/Voxen"
cp Voxen/Info.plist "$APP_DIR/Contents/Info.plist"
cp Voxen/Resources/voxen-logo-v1.png Voxen/Resources/Voxen.icns "$APP_DIR/Contents/Resources/"
codesign --force --sign - --identifier dev.voiceintent.router \
  --options runtime --entitlements Voxen/Voxen.entitlements "$APP_DIR"
printf 'Built %s\n' "$APP_DIR"
