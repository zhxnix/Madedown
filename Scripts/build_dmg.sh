#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/Madedown.app"
STAGING_DIR="$ROOT_DIR/.build/Madedown-dmg"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Packaging/Info.plist")"
DMG_PATH="$ROOT_DIR/dist/Madedown-$VERSION.dmg"

"$ROOT_DIR/Scripts/build_app_bundle.sh" >/dev/null

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
ditto "$APP_DIR" "$STAGING_DIR/Madedown.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "Madedown" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

hdiutil verify "$DMG_PATH" >/dev/null

MOUNT_DIR="$(mktemp -d /tmp/Madedown-dmg.XXXXXX)"
cleanup() {
  hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || true
  rmdir "$MOUNT_DIR" >/dev/null 2>&1 || true
}
trap cleanup EXIT

hdiutil attach "$DMG_PATH" \
  -readonly \
  -nobrowse \
  -noautoopen \
  -mountpoint "$MOUNT_DIR" >/dev/null

test -d "$MOUNT_DIR/Madedown.app"
test -L "$MOUNT_DIR/Applications"
codesign --verify --deep --strict "$MOUNT_DIR/Madedown.app"

echo "$DMG_PATH"
