# dmgbuild settings for Marc's disk image. Run through scripts/make-dmg.sh, which passes
# -D app=<path to Marc.app> -D background=<path to the background TIFF>.
# The window and icon positions match design/render-dmg-background.swift.
import os.path

application = defines["app"]  # noqa: F821 (provided by dmgbuild)
app_name = os.path.basename(application)

format = "UDZO"
files = [application]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(application, "Contents", "Resources", "AppIcon.icns")
background = defines["background"]  # noqa: F821

window_rect = ((200, 140), (660, 420))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True
include_list_view_settings = False

arrange_by = None
icon_size = 128
text_size = 13
label_pos = "bottom"
icon_locations = {app_name: (180, 190), "Applications": (480, 190)}
