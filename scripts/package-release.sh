#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

BUNDLE_VERSION="$(plutil -extract CFBundleShortVersionString raw Voxen/Info.plist)"
REQUESTED_VERSION="${1:-v$BUNDLE_VERSION}"

if [[ "$REQUESTED_VERSION" != "v$BUNDLE_VERSION" ]]; then
  printf 'Release version %s does not match Info.plist version v%s\n' "$REQUESTED_VERSION" "$BUNDLE_VERSION" >&2
  exit 1
fi

bash scripts/build.sh
codesign --verify --deep --strict build/Voxen.app

RELEASE_DIR="$PWD/release"
ARCHIVE_NAME="Voxen-macOS-arm64.zip"
mkdir -p "$RELEASE_DIR"
rm -f "$RELEASE_DIR/$ARCHIVE_NAME" "$RELEASE_DIR/$ARCHIVE_NAME.sha256"

ditto --noextattr --norsrc -c -k --keepParent \
  build/Voxen.app "$RELEASE_DIR/$ARCHIVE_NAME"

VERIFY_DIR="$(mktemp -d)"
trap 'rm -rf "$VERIFY_DIR"' EXIT
ditto -x -k "$RELEASE_DIR/$ARCHIVE_NAME" "$VERIFY_DIR"
codesign --verify --deep --strict "$VERIFY_DIR/Voxen.app"

(
  cd "$RELEASE_DIR"
  shasum -a 256 "$ARCHIVE_NAME" > "$ARCHIVE_NAME.sha256"
)

printf 'Packaged release/%s\n' "$ARCHIVE_NAME"
