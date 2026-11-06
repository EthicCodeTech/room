# dmgbuild settings for the Room disk image. Run by scripts/package.sh; app and bg come from -D.
import os
app = defines["app"]          # path to Room.app
bg = defines["bg"]            # background image (a multi-resolution TIFF)
icon = defines.get("icon")    # volume icon (.icns)

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
background = bg
if icon:
    icon = icon
window_rect = ((200, 120), (660, 432))   # content area is 660 x 400 below the title bar
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 112
text_size = 13
icon_locations = {
    os.path.basename(app): (165, 255),
    "Applications": (495, 255),
}
