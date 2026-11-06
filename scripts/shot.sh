#!/bin/bash
# Captures only the Room window (not the rest of the screen). Usage: scripts/shot.sh out.png
SWIFT_SRC=$(mktemp -t winid).swift
cat > "$SWIFT_SRC" << 'SW'
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
var best = (id: 0, area: 0.0)
let wantSmall = CommandLine.arguments.contains("small")
for w in list where (w[kCGWindowOwnerName as String] as? String) == "Room" {
    let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
    let area = (b["Width"] ?? 0) * (b["Height"] ?? 0)
    if (b["Width"] ?? 0) < 400 { continue }
    if best.id == 0 || (wantSmall ? area < best.area : area > best.area) { best = (w[kCGWindowNumber as String] as? Int ?? 0, area) }
}
if best.id != 0 { print(best.id) }
SW
ID=$(swift "$SWIFT_SRC" "$2" 2>/dev/null | head -1)
[ -z "$ID" ] && { echo "no Room window found" >&2; exit 1; }
screencapture -x -o -l "$ID" "$1"
