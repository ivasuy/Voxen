#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
ARCH="${VOXEN_ARCH:-$(uname -m)}"
SOURCES=()
while IFS= read -r file; do SOURCES+=("$file"); done < <(find VoiceIntentRouter -name '*.swift' ! -name 'VoiceIntentRouterApp.swift' -print | sort)
xcrun swiftc -swift-version 5 -target "$ARCH-apple-macos14.0" \
  -module-cache-path "$PWD/build/module-cache" -parse-as-library \
  "${SOURCES[@]}" Tests/CoreTests.swift -o build/CoreTests
build/CoreTests
