#!/usr/bin/env bash
# Builds ScratchMate.app from the SPM executable.
# The bundle is what lets the URL scheme (scratchmate://), LSUIElement (no Dock)
# and the global hotkey behave like a real app.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
APP_NAME="ScratchMate"
BUNDLE_ID="com.leonardolima.scratchmate"
VERSION="0.1.0"
FEED_URL="https://raw.githubusercontent.com/leonardocandiani/scratchmate/main/appcast.xml"
ED_PUB="$(cat Branding/ed_public.key 2>/dev/null || echo 'REPLACE_WITH_ED_PUBLIC_KEY')"

echo "==> Building ($CONFIG)…"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"
APP_DIR="dist/${APP_NAME}.app"
MACOS_DIR="${APP_DIR}/Contents/MacOS"
RES_DIR="${APP_DIR}/Contents/Resources"

echo "==> Assembling bundle at ${APP_DIR}…"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"

cp "${BIN_PATH}/scratchmate" "${MACOS_DIR}/scratchmate"

# Icon: generate if missing and copy into the bundle.
if [ ! -f Branding/ScratchMate.icns ]; then
    echo "==> Generating icon…"
    swift Branding/make-icon.swift Branding >/dev/null 2>&1 || echo "   (icon generation failed)"
fi
[ -f Branding/ScratchMate.icns ] && cp Branding/ScratchMate.icns "${RES_DIR}/ScratchMate.icns"

# Bundled release notes for the What's New window.
[ -f WhatsNew.md ] && cp WhatsNew.md "${RES_DIR}/WhatsNew.md"

# Embed Sparkle.framework so the bundle launches standalone (the binary links
# @rpath/Sparkle.framework); without this the assembled .app crashes at launch.
SPARKLE_FW="$(find "$BIN_PATH" -name 'Sparkle.framework' -maxdepth 2 2>/dev/null | head -1)"
if [ -n "$SPARKLE_FW" ]; then
    echo "==> Embedding Sparkle.framework…"
    mkdir -p "${APP_DIR}/Contents/Frameworks"
    cp -R "$SPARKLE_FW" "${APP_DIR}/Contents/Frameworks/"
    install_name_tool -add_rpath "@executable_path/../Frameworks" "${MACOS_DIR}/scratchmate" 2>/dev/null || true
fi

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>     <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>      <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>      <string>scratchmate</string>
    <key>CFBundleIconFile</key>        <string>ScratchMate</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>${VERSION}</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>LSUIElement</key>             <true/>
    <key>SUEnableAutomaticChecks</key> <true/>
    <key>SUFeedURL</key>               <string>${FEED_URL}</string>
    <key>SUPublicEDKey</key>           <string>${ED_PUB}</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>    <string>${BUNDLE_ID}</string>
            <key>CFBundleURLSchemes</key>
            <array><string>scratchmate</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

echo "==> Signing (ad-hoc)…"
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || echo "   (ad-hoc codesign failed, continuing unsigned)"

echo "==> Done: ${APP_DIR}"
echo "    Open:    open ${APP_DIR}"
echo "    Register URL scheme: open -a \"\$PWD/${APP_DIR}\""
