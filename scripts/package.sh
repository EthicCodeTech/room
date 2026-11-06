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

# The disk image: Room on the left, Applications on the right, over the brand background.
# dmgbuild writes the window layout directly (no Finder scripting); it lives in a local venv.
VENV=".build/dmgvenv"
[ -x "$VENV/bin/dmgbuild" ] || { python3 -m venv "$VENV" && "$VENV/bin/pip" install -q dmgbuild; }
BG="$(mktemp -d)/background.tiff"
tiffutil -cathidpicheck Brand/room-dmg-background.png Brand/room-dmg-background@2x.png -out "$BG" 2>/dev/null
"$VENV/bin/dmgbuild" -s scripts/dmg-settings.py -D app="$APP" -D bg="$BG" -D icon=Brand/RoomVolume.icns "Room" "$DMG" >/dev/null
[ -n "${DEVELOPER_ID:-}" ] && codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"

echo
echo "built:"
for f in "$DMG" "$ZIP"; do printf "  %s  %s  sha256 %s\n" "$f" "$(du -h "$f" | cut -f1)" "$(shasum -a 256 "$f" | cut -d' ' -f1 | cut -c1-16)..."; done
