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

DARK MODE
Room-Dark.iconset/ + Room-Dark.icns    Dark appearance app icon, all sizes
  (macOS 26: add as the Dark appearance in your asset catalog)
room-favicon-dark-16/32/48.png         White door, for dark tabs and backgrounds
room-og-image-dark.png                 1200 x 630 social preview, Obsidian
room-dmg-background-dark.png / @2x     Installer background, Obsidian
room-about-dark.png                    About window artwork for dark appearance
Menu bar icon needs no dark version: as a template image, macOS tints it.

HOW ROOM USES THESE (repo notes)
Room.icon                      Icon Composer source, compiled by scripts/bundle.sh into Assets.car. Two groups
                               (light door on a light tile, light door on a dark tile) swapped with group-level
                               hidden-specializations, so Dock, Finder and Launchpad follow the system theme.
room-dmg-background-adaptive.* Installer background used by scripts/package.sh. Transparent, in neutral greys,
                               so the Finder window's own light or dark material shows through. The fixed
                               light and dark artwork stay in the repo (room-dmg-background.*, dark/).
dark/Room-Dark.icns            Volume icon of the disk image. A volume icon cannot follow the theme, so it is the
                               dark tile, which is legible on light and dark title bars.
web/room-favicon-dark-*.png    Linked from the website with prefers-color-scheme: dark.
Menu bar icon and in-app logo  Template image and DS.text, so they follow the theme too.
