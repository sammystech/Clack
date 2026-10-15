# dmgbuild settings for the Clack installer window.
#   .venv/bin/dmgbuild -s dmg_settings.py -D app=path/to/Clack.app Clack dist/Clack.dmg
# Icon centres must match Tools/make_dmg_background.swift. The in-app updater mounts this
# same DMG and copies Clack.app from its root.
import os.path

app = defines.get("app", "Clack.app")  # noqa: F821 (injected by dmgbuild)

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = defines.get("volicon", None)  # noqa: F821
background = "Tools/dmg/background.tiff"

window_rect = ((200, 140), (660, 420))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 112
text_size = 13
icon_locations = {
    os.path.basename(app): (170, 210),
    "Applications": (490, 210),
}
# No hide_extensions: it writes com.apple.FinderInfo onto the bundle, which fails
# `codesign --verify --strict`, the check the in-app updater runs before installing.
