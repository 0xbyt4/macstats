#!/bin/sh
# Builds a release binary and wraps it in build/MacStats.app (ad-hoc signed).
set -eu

cd "$(dirname "$0")/.."

swift build -c release --product MacStats
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/MacStats.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/MacStats" "$APP/Contents/MacOS/MacStats"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "Created $APP"
