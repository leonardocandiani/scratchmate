#!/usr/bin/env bash
# Packages dist/ScratchMate.app into a compressed DMG with a /Applications shortcut,
# and generates the SHA-256 checksum. Runs after build-app.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="ScratchMate"
VERSION="$(tr -d ' \n' < VERSION)"
APP_DIR="dist/${APP_NAME}.app"
DMG="dist/${APP_NAME}-v${VERSION}-macOS.dmg"

[ -d "$APP_DIR" ] || { echo "Run Scripts/build-app.sh first."; exit 1; }

echo "==> Building DMG…"
STAGING="$(mktemp -d)"
cp -R "$APP_DIR" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

shasum -a 256 "$DMG" | awk '{print $1}' > "${DMG}.sha256"
echo "==> DMG: ${DMG}"
echo "    SHA-256: $(cat "${DMG}.sha256")"
echo "    Size: $(stat -f%z "$DMG") bytes"
