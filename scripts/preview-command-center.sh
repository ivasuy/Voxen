#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
cp VoiceIntentRouter/Resources/voxen-logo-v1.png build/
SOURCES=()
while IFS= read -r file; do SOURCES+=("$file"); done < <(find VoiceIntentRouter -name '*.swift' ! -name 'VoiceIntentRouterApp.swift' -print | sort)
xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 \
  -module-cache-path "$PWD/build/module-cache" -parse-as-library \
  "${SOURCES[@]}" Tests/CommandCenterPreview.swift -o build/CommandCenterPreview
build/CommandCenterPreview
