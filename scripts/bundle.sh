#!/bin/bash
# Builds Room and packages dist/Room.app (ad-hoc signed). Usage: scripts/bundle.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
APP="dist/Room.app"

if ! out=$(./scripts/swiftw.sh build -c "$CONFIG" 2>&1); then echo "BUILD FAILED:" >&2; echo "$out" | grep -E "error" | head -8 >&2; exit 1; fi
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Room" "$APP/Contents/MacOS/Room"
cp -R Sources/Room/Resources/Fonts "$APP/Contents/Resources/Fonts"

ICONSET="$(mktemp -d)/AppIcon.iconset"
"$BIN/room-icon" "$ICONSET" everyday >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>in.ethiccode.room</string>
  <key>CFBundleName</key><string>Room</string>
  <key>CFBundleDisplayName</key><string>Room</string>
  <key>CFBundleExecutable</key><string>Room</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSDesktopFolderUsageDescription</key><string>Room measures your Desktop to show what is using your space. Nothing leaves your Mac.</string>
  <key>NSDocumentsFolderUsageDescription</key><string>Room measures your Documents folder to show what is using your space. Nothing leaves your Mac.</string>
  <key>NSDownloadsFolderUsageDescription</key><string>Room measures your Downloads folder to find installers and old files. Nothing leaves your Mac.</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null 2>&1
echo "built $APP ($CONFIG)"
