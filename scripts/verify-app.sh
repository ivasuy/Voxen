#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
codesign --verify --deep --strict build/Voxen.app
xcrun swiftc -module-cache-path "$PWD/build/module-cache" Tests/BundleSmoke.swift -o build/BundleSmoke
build/BundleSmoke
xcrun swiftc -module-cache-path "$PWD/build/module-cache" Tests/LaunchSmoke.swift -o build/LaunchSmoke
build/LaunchSmoke "$PWD/build/Voxen.app"
