#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR="$PWD/build"
APP_DIR="$BUILD_DIR/Voxen.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$BUILD_DIR/module-cache"
SOURCES=()
while IFS= read -r file; do SOURCES+=("$file"); done < <(find VoiceIntentRouter -name '*.swift' -print | sort)
xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 \
  -module-cache-path "$BUILD_DIR/module-cache" -O -parse-as-library \
  "${SOURCES[@]}" -o "$APP_DIR/Contents/MacOS/VoiceIntentRouter"
cp VoiceIntentRouter/Info.plist "$APP_DIR/Contents/Info.plist"
cp VoiceIntentRouter/Resources/voxen-logo-v1.png VoiceIntentRouter/Resources/Voxen.icns "$APP_DIR/Contents/Resources/"
codesign --force --sign - --identifier dev.voiceintent.router \
  --options runtime --entitlements VoiceIntentRouter/VoiceIntentRouter.entitlements "$APP_DIR"
printf 'Built %s\n' "$APP_DIR"
