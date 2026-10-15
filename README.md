# Clack

Mechanical keyboard sounds for every keystroke on your Mac, in a native Liquid Glass app (macOS 26+).

- Menu-bar panel and a small main window: sound pack, volume, mute
- Global mute shortcut (default Control-Option-Command-M), start at login, key-up sounds
- Built-in synthesized switch sounds, plus the classic Mechvibes packs (MIT, see `Packs/MECHVIBES-LICENSE.txt`)
- Loads any Mechvibes-format pack from `~/mechvibes_custom`, `~/Library/Application Support/Clack/Packs`, or folders you add

Clack needs **Input Monitoring** (System Settings > Privacy & Security > Input Monitoring) to hear key presses. It never records or sends what you type.

## Build

    xcodegen generate && open Clack.xcodeproj

## Release (Developer ID + notarization + DMG + GitHub release)

    ./release.sh 1.0 "notes"
