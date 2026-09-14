#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP_DIR="$PWD/build/Voxen.app"
codesign --verify --deep --strict "$APP_DIR"
open "$APP_DIR"
