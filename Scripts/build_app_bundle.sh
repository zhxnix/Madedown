#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/Madedown.app"
LEGACY_APP_DIR="$ROOT_DIR/dist/MarkdownNotepad.app"
EXECUTABLE="$ROOT_DIR/.build/release/Madedown"
APP_ICON="$ROOT_DIR/Assets/Logo/madedown-app-icon.png"
TITLEBAR_WORDMARK="$ROOT_DIR/Assets/Logo/madedown-titlebar-wordmark.png"
ICONSET_DIR="$ROOT_DIR/.build/Madedown.iconset"

swift "$ROOT_DIR/Scripts/generate_brand_assets.swift" \
  "$ROOT_DIR/Assets/Logo/madedown-square-logo-transparent.png" \
  "$ROOT_DIR/Assets/Logo/madedown-wordmark-transparent.png" \
  "$APP_ICON" \
  "$TITLEBAR_WORDMARK"

swift build -c release --package-path "$ROOT_DIR"

rm -rf "$APP_DIR" "$LEGACY_APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

make_icon() {
  local size="$1"
  local filename="$2"
  sips -z "$size" "$size" "$APP_ICON" --out "$ICONSET_DIR/$filename" >/dev/null
}

make_icon 16 icon_16x16.png
make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png
make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png
make_icon 1024 icon_512x512@2x.png

cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/Madedown"
cp "$ROOT_DIR/Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$TITLEBAR_WORDMARK" "$APP_DIR/Contents/Resources/MadedownWordmark.png"
iconutil -c icns -o "$APP_DIR/Contents/Resources/Madedown.icns" "$ICONSET_DIR"
chmod +x "$APP_DIR/Contents/MacOS/Madedown"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
fi

echo "$APP_DIR"
