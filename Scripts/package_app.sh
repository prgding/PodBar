#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
SIGNING_IDENTITY="$(python3 Scripts/signing.py identity)"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
mkdir -p "$PROJECT_ROOT/build"
STAGE="$(mktemp -d "$PROJECT_ROOT/build/package.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/PodBar.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/PodBar" "$APP/Contents/MacOS/PodBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
swift Scripts/GenerateIcon.swift "$STAGE/PodBar.iconset"
iconutil -c icns "$STAGE/PodBar.iconset" -o "$APP/Contents/Resources/PodBar.icns"
python3 Scripts/signing.py sign "$APP" "$SIGNING_IDENTITY"
codesign --verify --strict "$APP"
plutil -lint "$APP/Contents/Info.plist"
# Replace only this script's reproducible build artifact.
rm -rf "$PROJECT_ROOT/build/PodBar.app"
mv "$APP" "$PROJECT_ROOT/build/PodBar.app"
echo "$PROJECT_ROOT/build/PodBar.app"
