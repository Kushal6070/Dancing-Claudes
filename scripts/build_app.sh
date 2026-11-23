#!/usr/bin/env bash
# Builds "Vibe Clauding.app" into ./build (ad-hoc signed, ready to double-click).
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Vibe Clauding"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
CONFIG="${CONFIG:-release}"

echo "==> Compiling ($CONFIG)"
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

if [ ! -f "$BUILD_DIR/AppIcon.icns" ]; then
  echo "==> Rendering app icon"
  mkdir -p "$BUILD_DIR"
  rm -rf "$BUILD_DIR/AppIcon.iconset"
  swift scripts/make_icon.swift "$BUILD_DIR/AppIcon.iconset" >/dev/null
  iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$BUILD_DIR/AppIcon.icns"
fi

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/VibeClauding" "$APP/Contents/MacOS/VibeClauding"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BUILD_DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "==> Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP"

echo "Built: $APP"
echo "Run:   open \"$APP\""
