#!/usr/bin/env bash
# Release build of ScratchMate: universal binary (arm64 + x86_64), .app bundle
# with icon, complete Info.plist (Sparkle + URL scheme), Sparkle embed if present
# and ad-hoc signing with a pinned Designated Requirement (makes TCC persist across
# rebuilds, pattern inherited from Krit). No Xcode project dependency.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="ScratchMate"
BUNDLE_ID="com.leonardolima.scratchmate"
VERSION="$(tr -d ' \n' < VERSION)"
BUILD_STAMP="$(date +%Y%m%d.%H%M)"   # CFBundleVersion for Sparkle comparison
FEED_URL="https://raw.githubusercontent.com/leonardocandiani/scratchmate/main/appcast.xml"
# EdDSA public key for Sparkle, embedded in Info.plist as SUPublicEDKey. Generate
# the keypair once with Sparkle's generate_keys: the public key goes here in
# Branding/ed_public.key (committed), the private key stays in the maintainer's
# login Keychain (and is exported to the SPARKLE_PRIVATE_KEY CI secret via
# `generate_keys -x`, used by release.sh). Do NOT invent a key: until the real one
# is committed this falls back to a placeholder and Sparkle update checks will fail.
ED_PUB="$(cat Branding/ed_public.key 2>/dev/null || echo 'REPLACE_WITH_ED_PUBLIC_KEY')"
SIGN_ID="${SCRATCHMATE_CODESIGN_IDENTITY:--}"   # '-' = ad-hoc; ou Developer ID via env

echo "==> Building universal (arm64 + x86_64), release…"
swift build -c release --arch arm64 --arch x86_64

BIN_PATH="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
APP_DIR="dist/${APP_NAME}.app"
MACOS_DIR="${APP_DIR}/Contents/MacOS"
RES_DIR="${APP_DIR}/Contents/Resources"
FRAMEWORKS_DIR="${APP_DIR}/Contents/Frameworks"

echo "==> Assembling bundle…"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"
cp "${BIN_PATH}/scratchmate" "${MACOS_DIR}/scratchmate"

# Icon
if [ ! -f Branding/ScratchMate.icns ]; then
    swift Branding/make-icon.swift Branding >/dev/null 2>&1 || true
fi
[ -f Branding/ScratchMate.icns ] && cp Branding/ScratchMate.icns "${RES_DIR}/ScratchMate.icns"

# Bundled release notes for the What's New window.
[ -f WhatsNew.md ] && cp WhatsNew.md "${RES_DIR}/WhatsNew.md"

# Embed Sparkle.framework, if the dependency is present.
SPARKLE_FW="$(find "$BIN_PATH" -name 'Sparkle.framework' -maxdepth 2 2>/dev/null | head -1)"
if [ -n "$SPARKLE_FW" ]; then
    echo "==> Embedding Sparkle.framework…"
    mkdir -p "$FRAMEWORKS_DIR"
    cp -R "$SPARKLE_FW" "$FRAMEWORKS_DIR/"
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
    <key>CFBundleVersion</key>         <string>${BUILD_STAMP}</string>
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

echo "==> Signing (${SIGN_ID})…"
if [ -n "$SPARKLE_FW" ]; then
    codesign --force --options runtime --sign "$SIGN_ID" "${FRAMEWORKS_DIR}/Sparkle.framework" 2>/dev/null || true
fi
# Designated Requirement pinned to the identifier: TCC/permissions persist across rebuilds.
codesign --force --sign "$SIGN_ID" \
    --identifier "$BUNDLE_ID" \
    -r="designated => identifier \"$BUNDLE_ID\"" \
    "$APP_DIR" 2>&1 | tail -1 || echo "   (codesign failed, continuing unsigned)"

echo "==> Done: ${APP_DIR}  (v${VERSION}, build ${BUILD_STAMP})"
