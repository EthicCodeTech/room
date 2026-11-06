Room · Cinnabar by EthicCode

Mark: a doorway (a room, and the way into more space) with a sindoor
doorknob (#F2542D). Wordmark: "room", Parkinsans SemiBold, outlined.

MARK          room-mark-dark / light / black / white (.svg, .png 512)
LOCKUPS       room-lockup-dark / light (.svg, .png)

MACOS APP ICON
room-appicon-light.png / .svg   Default icon (Apple 824px grid in 1024)
room-appicon-dark.png / .svg    Dark appearance variant
Room.iconset/                   All sizes 16 to 512 @1x and @2x
Room.icns                       Ready to use
To rebuild on a Mac:  iconutil -c icns Room.iconset

MENU BAR
RoomMenuBarTemplate.png / @2x / @3x   18pt, black on transparent.
Load as a template image so macOS tints it for light and dark menu bars:
  NSImage(named: "RoomMenuBarTemplate")?.isTemplate = true

WEB
room-favicon.svg (adapts to light and dark), room-favicon-16/32/48.png, favicon.ico
room-og-image.png   1200 x 630 social preview

DISTRIBUTION
room-dmg-background.png (660 x 400) and @2x
  Place Room.app on the left of the arrow, Applications on the right.
room-about.png      About window artwork (600 x 340 @2x)

RULES
One sindoor dot (the doorknob). Never recolour it except in single-colour
versions. Keep the floor line: it grounds the mark at small sizes.

RoomVolume.icns   Disk image volume icon: the dark tile, so it stays visible in a light Finder title bar.

Room.icon         Icon Composer source used by scripts/bundle.sh (compiled with actool). One design for light and dark: the light door on the dark tile, so it stays legible when macOS darkens icons. Room.icns is the original flat export, kept for reference.
