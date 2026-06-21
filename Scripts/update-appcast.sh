#!/usr/bin/env bash
# Inserts a new <item> into appcast.xml (newest first, right after <language>).
# Usage: update-appcast.sh <version> <build> <dmg_path> <ed_signature> [notes_html]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?version}"; BUILD="${2:?build stamp}"; DMG="${3:?dmg path}"
ED_SIG="${4:?EdDSA signature}"; NOTES="${5:-Fixes and improvements.}"
REPO="leonardocandiani/scratchmate"
LENGTH="$(stat -f%z "$DMG")"
DMG_NAME="$(basename "$DMG")"
URL="https://github.com/${REPO}/releases/download/v${VERSION}/${DMG_NAME}"
PUBDATE="$(date -u +'%a, %d %b %Y %H:%M:%S +0000')"

ITEM="    <item>
      <title>ScratchMate ${VERSION}</title>
      <pubDate>${PUBDATE}</pubDate>
      <sparkle:version>${BUILD}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[${NOTES}]]></description>
      <enclosure url=\"${URL}\" length=\"${LENGTH}\" type=\"application/octet-stream\" sparkle:edSignature=\"${ED_SIG}\" />
    </item>"

# Insert the item right after the </language> line. The item is multi-line and
# contains quotes, so it is read from a file (awk -v mangles newlines/quotes).
item_file="$(mktemp)"
printf '%s\n' "$ITEM" > "$item_file"
tmp="$(mktemp)"
awk -v itemfile="$item_file" '
  { print }
  /<language>.*<\/language>/ && !done {
    while ((getline line < itemfile) > 0) print line
    close(itemfile)
    done=1
  }
' appcast.xml > "$tmp" && mv "$tmp" appcast.xml
rm -f "$item_file"

echo "==> appcast.xml updated with v${VERSION} (build ${BUILD})"
