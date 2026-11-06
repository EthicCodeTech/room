#!/bin/bash
# Builds Room and packages dist/Room.app (ad-hoc signed). Usage: scripts/bundle.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
APP="dist/Room.app"

# Release builds are universal (Apple silicon + Intel); debug stays native for speed.
ARCHS=()
if [ "$CONFIG" = "release" ]; then ARCHS=(--arch arm64 --arch x86_64); fi

if ! out=$(./scripts/swiftw.sh build -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"} 2>&1); then echo "BUILD FAILED:" >&2; echo "$out" | grep -E "error" | head -8 >&2; exit 1; fi
BIN="$(swift build -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)"

rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Room" "$APP/Contents/MacOS/Room"
cp -R Sources/Room/Resources/Fonts "$APP/Contents/Resources/Fonts"

# Icon Composer bundle -> Assets.car (light and dark appearances) + Room.icns for older readers.
ICON_OUT="$(mktemp -d)"
xcrun actool "$PWD/Brand/Room.icon" --compile "$ICON_OUT" --output-format human-readable-text --notices --warnings --errors \
  --output-partial-info-plist "$ICON_OUT/partial.plist" --app-icon Room --include-all-app-icons \
  --enable-on-demand-resources NO --development-region en --target-device mac --minimum-deployment-target 26.0 --platform macosx >/dev/null
cp "$ICON_OUT/Assets.car" "$ICON_OUT/Room.icns" "$APP/Contents/Resources/"
cp Brand/RoomMenuBarTemplate.png Brand/RoomMenuBarTemplate@2x.png Brand/RoomMenuBarTemplate@3x.png "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>in.ethiccode.room</string>
  <key>CFBundleName</key><string>Room</string>
  <key>CFBundleDisplayName</key><string>Room</string>
  <key>CFBundleExecutable</key><string>Room</string>
  <key>CFBundleIconFile</key><string>Room</string>
  <key>CFBundleIconName</key><string>Room</string>
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
