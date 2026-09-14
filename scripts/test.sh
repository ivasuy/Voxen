#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
ARCH="${VOXEN_ARCH:-$(uname -m)}"
SWIFT_FLAGS=()
if [[ "${VOXEN_STRICT_CONCURRENCY:-0}" == "1" ]]; then
  SWIFT_FLAGS=(-strict-concurrency=complete -warnings-as-errors)
fi
SOURCES=()
while IFS= read -r file; do SOURCES+=("$file"); done < <(find Voxen -name '*.swift' ! -name 'VoxenApp.swift' -print | sort)
xcrun swiftc -swift-version 5 -target "$ARCH-apple-macos14.0" \
  -module-cache-path "$PWD/build/module-cache" -parse-as-library \
  "${SWIFT_FLAGS[@]}" "${SOURCES[@]}" Tests/CoreTests.swift -o build/CoreTests
build/CoreTests
