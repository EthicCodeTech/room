#!/bin/bash
# Sends the signed disk image to Apple for notarization, then staples the ticket so it opens offline.
# One-time setup (needs a paid Apple Developer account):
#   1. Create a "Developer ID Application" certificate in Xcode (Settings, Accounts, Manage Certificates).
#   2. xcrun notarytool store-credentials "room-notary"      (asks for your Apple ID and an app-specific password;
#                                                              it stores them in your Keychain, not in any file)
#   3. Copy .env.example to .env and fill in DEVELOPER_ID and NOTARY_PROFILE.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .env ] && { set -a; source .env; set +a; }
: "${DEVELOPER_ID:?Set DEVELOPER_ID in .env (see .env.example)}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE in .env (see .env.example)}"
VERSION="${VERSION:-1.0.0}"
DMG="dist/Room-$VERSION.dmg"

./scripts/package.sh
echo "submitting $DMG to Apple (usually a few minutes)..."
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature -vv "$DMG" || true
echo "done: $DMG opens on any Mac with a double-click."
