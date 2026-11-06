#!/bin/bash
# Builds Room and packages it for sharing: dist/Room-<version>.dmg and dist/Room-<version>.zip.
# With DEVELOPER_ID set (see .env.example) the app is signed with your Developer ID and hardened runtime,
# which is the first step toward notarization (scripts/notarize.sh). Without it, the app is ad-hoc signed.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .env ] && { set -a; source .env; set +a; }
VERSION="${VERSION:-1.0.0}"
APP="dist/Room.app"

./scripts/bundle.sh release

if [ -n "${DEVELOPER_ID:-}" ]; then
  echo "signing with: $DEVELOPER_ID"
  codesign --force --deep --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"
fi

ZIP="dist/Room-$VERSION.zip"; DMG="dist/Room-$VERSION.dmg"
rm -f "$ZIP" "$DMG"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

STAGE="$(mktemp -d)/Room"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/Room.app"
ln -s /Applications "$STAGE/Applications"
cp scripts/dmg-readme.txt "$STAGE/Read me first.txt"
hdiutil create -volname "Room" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
[ -n "${DEVELOPER_ID:-}" ] && codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"

echo
echo "built:"
for f in "$DMG" "$ZIP"; do printf "  %s  %s  sha256 %s\n" "$f" "$(du -h "$f" | cut -f1)" "$(shasum -a 256 "$f" | cut -d' ' -f1 | cut -c1-16)..."; done
