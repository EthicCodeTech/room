#!/bin/bash
# Runs `swift <args>` and retries when a Swift macro plugin (Testing, SwiftUI, Observation) fails to load,
# a known flake with the Command Line Tools toolchain. Usage: scripts/swiftw.sh build -c release
cd "$(dirname "$0")/.."
for attempt in 1 2 3 4; do
  out=$(swift "$@" 2>&1); code=$?
  if echo "$out" | grep -q "plugin for module 'SwiftUIMacros' not found"; then
    echo "SwiftUI needs the full Xcode toolchain (the Command Line Tools lack SwiftUIMacros)." >&2
    echo "One-time fix, in Terminal:  sudo xcodebuild -license accept  &&  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
    exit 2
  fi
  if echo "$out" | grep -qE "plugin for module '[A-Za-z]+' not found"; then
    echo "(attempt $attempt: macro plugin flake, retrying)" >&2; continue
  fi
  echo "$out"; exit $code
done
echo "$out"; exit 1
