#!/bin/bash
# Engine tests only need RoomCore, so build just that + the test target (the SwiftUI app target needs full Xcode).
cd "$(dirname "$0")/.."
./scripts/swiftw.sh build --target RoomCoreTests >/dev/null 2>&1 || { ./scripts/swiftw.sh build --target RoomCoreTests >&2; exit $?; }
exec ./scripts/swiftw.sh test --skip-build "$@"
