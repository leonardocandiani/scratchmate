#!/usr/bin/env bash
# Orchestrates a ScratchMate release (mirrors the Krit pipeline).
# Usage: release.sh <new-version> [--publish]
#   without --publish: bumps the version, builds, generates the DMG, signs (EdDSA)
#                      and updates the appcast LOCALLY; prints the git/gh commands for you to review.
#   with --publish: on top of the above, commits, creates the vX.Y.Z tag and the GitHub release.
set -euo pipefail
cd "$(dirname "$0")/.."

NEW_VERSION="${1:?usage: release.sh <version> [--publish]}"
PUBLISH="${2:-}"
BUILD_STAMP="$(date +%Y%m%d.%H%M)"
DMG="dist/ScratchMate-v${NEW_VERSION}-macOS.dmg"

echo "==> Release ScratchMate v${NEW_VERSION}"
echo "$NEW_VERSION" > VERSION

# Changelog (Keep a Changelog).
DATE="$(date +%Y-%m-%d)"
[ -f CHANGELOG.md ] || printf '# Changelog\n\n' > CHANGELOG.md
tmp="$(mktemp)"
{ head -2 CHANGELOG.md; printf '## [%s] - %s\n\n- \n\n' "$NEW_VERSION" "$DATE"; tail -n +3 CHANGELOG.md; } > "$tmp" && mv "$tmp" CHANGELOG.md

Scripts/build-app.sh
Scripts/make-dmg.sh

# Sign the DMG with Sparkle's EdDSA key, if the tool is available.
# Private key:
#   - local: read from the maintainer's Keychain (sign_update default);
#   - CI: exported to base64 via `generate_keys -x` and passed in SPARKLE_PRIVATE_KEY
#         (secret); here we write it to a temp file and pass it with -f.
# The matching public key lives in Branding/ed_public.key (committed).
ED_SIG=""
SIGN_TOOL="$(find .build -name 'sign_update' -type f 2>/dev/null | head -1)"
if [ -n "$SIGN_TOOL" ] && [ -f "$DMG" ]; then
    KEY_ARGS=()
    KEY_FILE=""
    if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
        KEY_FILE="$(mktemp)"
        printf '%s' "$SPARKLE_PRIVATE_KEY" > "$KEY_FILE"
        KEY_ARGS=(-f "$KEY_FILE")
    fi
    ED_SIG="$("$SIGN_TOOL" "${KEY_ARGS[@]}" "$DMG" 2>/dev/null | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
    [ -n "$KEY_FILE" ] && rm -f "$KEY_FILE"
    [ -n "$ED_SIG" ] && Scripts/update-appcast.sh "$NEW_VERSION" "$BUILD_STAMP" "$DMG" "$ED_SIG"
fi
[ -z "$ED_SIG" ] && echo "!! sign_update unavailable or no key; appcast NOT signed (see docs/SETUP.md)."

# Print the DMG SHA-256 (produced by make-dmg.sh) so the Cask can be updated.
if [ -f "${DMG}.sha256" ]; then
    echo "==> Cask sha256 (v${NEW_VERSION}): $(cat "${DMG}.sha256")"
fi

if [ "$PUBLISH" = "--publish" ]; then
    echo "==> Publishing…"
    git add VERSION CHANGELOG.md appcast.xml
    git commit -m "chore(release): v${NEW_VERSION}"
    git tag -a "v${NEW_VERSION}" -m "ScratchMate v${NEW_VERSION}"
    git push && git push --tags
    gh release create "v${NEW_VERSION}" "$DMG" "${DMG}.sha256" --title "ScratchMate v${NEW_VERSION}" --notes-file <(sed -n '/## \['"$NEW_VERSION"'\]/,/## \[/p' CHANGELOG.md | sed '$d')
else
    echo "==> Local ready. To publish, review and run:"
    echo "    git add VERSION CHANGELOG.md appcast.xml && git commit -m 'chore(release): v${NEW_VERSION}'"
    echo "    git tag -a v${NEW_VERSION} -m 'ScratchMate v${NEW_VERSION}' && git push && git push --tags"
    echo "    gh release create v${NEW_VERSION} ${DMG} ${DMG}.sha256 --title 'ScratchMate v${NEW_VERSION}'"
fi
