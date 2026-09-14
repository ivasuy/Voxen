#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
codesign --verify --deep --strict build/Voxen.app
xcrun swiftc -module-cache-path "$PWD/build/module-cache" Tests/Relaunch.swift -o build/Relaunch
build/Relaunch
