#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
SOURCES=()
while IFS= read -r file; do SOURCES+=("$file"); done < <(find VoiceIntentRouter -name '*.swift' ! -name 'VoiceIntentRouterApp.swift' -print | sort)
xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 \
  -module-cache-path "$PWD/build/module-cache" -parse-as-library \
  "${SOURCES[@]}" Tests/IntentLive.swift -o build/IntentLive
build/IntentLive "$@"
