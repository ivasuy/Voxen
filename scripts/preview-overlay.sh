#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
cp Voxen/Resources/voxen-logo-v1.png build/
SOURCES=()
while IFS= read -r file; do SOURCES+=("$file"); done < <(find Voxen -name '*.swift' ! -name 'VoxenApp.swift' -print | sort)
xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 \
  -module-cache-path "$PWD/build/module-cache" -parse-as-library \
  "${SOURCES[@]}" Tests/OverlayPreview.swift -o build/OverlayPreview
build/OverlayPreview
