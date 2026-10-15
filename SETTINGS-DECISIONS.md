# Clack settings decisions

Source: the Mechvibes code itself, read-only. v2.3.4 is the installed app (unpacked at /tmp/app-replica-scratch/unpacked/src). v2.3.6 is the newest public tag (saved at /tmp/app-replica-scratch/v236/src). Every store key was confirmed by grepping both trees: `mechvibes-pack`, `mechvibes-volume`, `mechvibes-hidden`, `mechvibes-muted`, `mechvibes-start-minimized`, `mechvibes-active-volume`, `mechvibes-migrate-asked`, plus the IPC-only `mechvibes-mute-status`.

Existing Clack settings: none. As of 2026-10-14, /Users/samuelmittman/clack has no Swift sources (no project.yml, no Clack/ folder), so every KEEP or ADAPT row maps to NEW. The "Clack key" column gives the proposed `UserDefaults` key that build agents should use.

Surfaces in Clack:
- **Panel**: the main glass window or MenuBarExtra panel. It shows only pack, volume and mute.
- **Menu**: the menu bar item's right-click menu.
- **Settings**: the standard macOS Settings scene, with General, Sound, Packs and About panes.

## 1. Inventory of every Mechvibes setting

| # | Mechvibes surface | Setting | What it does | Default | Decision | Reason | Clack key / surface |
|---|---|---|---|---|---|---|---|
| 1 | Main window, select | Sound pack | Selects the active pack. The id is `default-<folder>` or `custom-<folder>`, and the list is grouped into Default and Custom optgroups. | First pack found, alphabetical (`cherrymx-black-abs`) | ADAPT | Core feature. Clack groups packs as Built-in and Custom, keeps the old pack playing until the new one decodes, and reverts the selection if loading fails. | NEW `selectedPackID` (String, `builtin-<slug>` / `custom-<folder>`). Panel picker. |
| 2 | Main window, link | Set random sound | Picks a random pack other than the current one, then saves it. It recurses forever when only one pack exists. | Action | KEEP | Owner asked for it. Disable it when fewer than 2 packs are loaded. | NEW action. Menu item and a Packs-pane button; Panel overflow only if it fits. |
| 3 | Main window, link | More sounds... | Opens mechvibes.com/sound-packs in the browser. | Link | DROP | The app makes no network calls and uses no Mechvibes branding. | n/a |
| 4 | Main window, slider | Volume | Linear gain `value/100`, applied on the next key press. Stored as a string. | 20 (v2.3.4), 50 (v2.3.6). Range 0 to 100 (0 to 200 in v2.3.6), step 5. | ADAPT | Core control. Store a Double 0...1, apply it live through the mixer, step 0.05, show the value as a percent. | NEW `volume` (Double, default 0.5). Panel slider. |
| 5 | Main window, slider (v2.3.6) | Volume above 100% | Extends the slider to 200% and shows yellow, orange and red bands above 100%. | On in v2.3.6 (max 200) | ADAPT | Useful for quiet packs. Keep it off by default and behind Settings, with one subtle tint instead of three bands. | NEW `allowBoost` (Bool, false). Settings > Sound. |
| 6 | Main window, checkbox row | Show Tray Icon | Creates or destroys the tray icon. Stored inverted as `mechvibes-hidden` (true means shown). There is no way back if both the tray and the window are hidden. | true (shown) | ADAPT | Keep, with a correct name and a recovery path: reopening the app from Finder, Spotlight or the Dock always shows the Panel. | NEW `showMenuBarIcon` (Bool, true). Settings > General. |
| 7 | Tray menu, checkbox | Mute | Stops the global key hook entirely (`iohook.stop()`) instead of zeroing volume. In v2.3.4 it exists only in the tray, and its checkmark goes stale. | false | KEEP | Core feature. Mute tears down the CGEventTap. The checkmark stays live, and Mute is a primary Panel control. | NEW `isMuted` (Bool, false). Panel toggle and Menu item. |
| 8 | Main window banner (v2.3.6) | "currently muted" banner | Reflects mute state in the window through the `mechvibes-mute-status` IPC message. | Hidden | ADAPT | Make it a small inline status in the Panel (the mute toggle's own state plus a dimmed press indicator), not a separate banner. | Derived from `isMuted`, no key. |
| 9 | Tray menu, checkbox | Enable at Startup | OS login item through `setLoginItemSettings`. In v2.3.4 the toggle reads an undefined property, so it can only enable. | Off | KEEP | Owner asked for it. Use `SMAppService.mainApp` and read the state back from `.status` so it can actually turn off. | NEW, no stored key (the OS holds it). Settings > General. |
| 10 | Tray > Extras (v2.3.6) | Start Minimized | Creates the window hidden, only when launched at login and the setting is on. A manual launch always shows the window. | false | KEEP | Owner asked for "start hidden". Keep the same rule: hidden only for login launches. | NEW `startHidden` (Bool, false). Settings > General, under the login toggle and disabled while that is off. |
| 11 | Tray > Extras (v2.3.6) | Active Volume Adjustment | Polls system output volume every 3 s and scales the click gain by `100/systemVolume`, so clicks stay equally loud. It divides by zero at 0 and shows "system sounds muted". | true | ADAPT | Interesting but it fights the user's volume keys. Offer it off by default, use a Core Audio property listener instead of polling, and clamp the multiplier to 4x. Owner should confirm (Q3). | NEW `constantLoudness` (Bool, false). Settings > Sound. |
| 12 | Tray menu, item | Mechvibes (show window) | Shows the Dock icon and the main window. | Action | KEEP | Basic navigation. | NEW Menu item "Open Clack". |
| 13 | Tray menu, item | Editor | Opens the 1200x600 visual pack editor. | Action | DROP | Owner's scope drops the pack Editor. | n/a |
| 14 | Tray menu, item (v2.3.4) / Folders submenu (v2.3.6) | Custom Folder / Custom Soundpacks | Reveals the custom packs folder in Finder. | Action | KEEP | Owner asked for it. | NEW action. Menu item and Settings > Packs. |
| 15 | Tray > Folders (v2.3.6) | Application Data | Reveals Electron's userData folder in Finder. | Action | DROP | Clack has nothing useful in Application Support besides Packs, which item 14 already covers. | n/a |
| 16 | Tray menu, item | Quit | Sets `isQuiting` and quits. Cmd+Q is otherwise blocked by the close handler (bug). | Action | KEEP | Clack's Cmd+Q also quits for real. | NEW Menu item and standard app menu. |
| 17 | Tray icon, clicks | Left-click menu, right-click window | Inverted from the macOS convention. | n/a | ADAPT | Left-click opens the Panel and right-click opens the Menu. | Behavior, no key. |
| 18 | Window, close button | Close hides the window and Dock icon | The app keeps running in the tray, and the Dock icon hides on close. | n/a | ADAPT | Cmd+W and close hide the window and switch the activation policy to `.accessory`. Whether the Dock icon shows while the window is open is Q4. | NEW `showDockIcon` (Bool, true while a window is open) only if the owner wants a toggle. Otherwise behavior only. |
| 19 | Startup (main.js) | Custom packs folder location | v2.3.4 uses `~/mechvibes_custom`, created at launch. v2.3.6 moves it to `<userData>/custom`. | `~/mechvibes_custom` | ADAPT | Read `~/mechvibes_custom` (and Mechvibes' v2.3.6 folder if present) in place and read-only. Clack's own imports go to `~/Library/Application Support/Clack/Packs`. The owner can add more folders. | NEW `customPackFolders` ([String] security-scoped bookmarks or paths; default includes `~/mechvibes_custom`). Settings > Packs list with + and -. |
| 20 | Startup dialog (v2.3.6) | Migrate old packs prompt | Offers to move `~/mechvibes_custom` into the new folder and delete the old one. "Don't ask again" sets `mechvibes-migrate-asked`. The guard is inverted, so the prompt only appears after that flag is set (bug). | false | DROP | Clack reads the old folder in place, so nothing needs moving or deleting. | n/a |
| 21 | Window reload / launch | Reload packs | Packs are rescanned only on window load or reload. There is no button. | Implicit | ADAPT | Owner asked for an explicit Reload. Also rescan when Settings opens, and through FSEvents on the pack folders. | NEW action. Settings > Packs "Reload Packs" button and Menu item. |
| 22 | `mechvibes://install <id>` URL scheme | Online pack installer | Downloads a pack manifest and files from mechvibes.com into the custom folder. It does no path sanitizing and reports errors as codes such as NOTFOUND. | Registered at launch | DROP | No network. Replaced by local "Add Pack..." (item 30). | n/a |
| 23 | Footer | Update check banner | Fetches GitHub releases/latest once per load and compares versions as strings (bug). | On | DROP | Owner's scope drops the auto-updater, and the app makes no network calls. | n/a |
| 24 | Footer | Credit, Home page, FAQs, donation links | External links. | n/a | DROP | Clutter and Mechvibes branding. | n/a |
| 25 | Footer | Version string | Shows "vX.Y.Z". | n/a | ADAPT | Show it in Settings > About only. | NEW About pane (reads the bundle version). |
| 26 | Debug window (v2.3.6) | Remote debugging toggle, debug code, logging level | Server-gated "Advanced" window. Sends hostname and username to beta.mechvibes.com. | Off | DROP | Owner's scope drops analytics, and this is a privacy risk. | n/a |
| 27 | userData flag file | Remote logging opt-in (`remote-logging-opt-in.txt`) | When the file exists, logs go to a third-party URL along with hostname and username. | Off | DROP | Same as item 26. | n/a |
| 28 | main.js | Local log file `~/mechvibes.log` | Info-level text log in the home folder. | On | ADAPT | Use `os.Logger` (subsystem `com.samuelmittman.clack`, categories `audio`, `packs`, `input`). Never log key identities. No setting. | Behavior, no key. |
| 29 | app.js | Key-repeat suppression | v2.3.4 ignores a key-down matching the last key-down until any key-up. v2.3.6 tracks a per-key pressed map. Not user-configurable. | Always on | ADAPT | Owner wants auto-repeat ignored by default. Use `kCGKeyboardEventAutorepeat` plus a per-key down set, and expose a toggle in Settings for anyone who wants repeat clicks. | NEW `playOnAutoRepeat` (Bool, false). Settings > Sound. |
| 30 | Editor > Import (closest equivalent) | Import a pack | Only exists as the Editor's JSON import. There is no "add pack folder" in the main app. | n/a | ADAPT | Replace with "Add Pack..." (an NSOpenPanel for a folder or .zip, plus drag and drop). Validate config.json, copy into Clack's Packs folder, sanitize names with `lastPathComponent`, and auto-select the new pack. | NEW action. Settings > Packs. |
| 31 | Pack config v2 (v2.3.6) | Key-up sounds | `<kc>-up` defines and the `soundup` fallback play on release. There is no user toggle; it plays whenever the pack defines them. | Plays when defined | ADAPT | Owner wants key-up sounds where the pack supports them. Add a toggle, on by default. The Clack synthesized packs also generate key-up variants. | NEW `playKeyUpSounds` (Bool, true). Settings > Sound. |
| 32 | main.js | Single instance, quit on shutdown | A second launch focuses the existing window. The app quits on the system shutdown event. | Always | KEEP | Correct behavior. SwiftUI and AppKit give both for free (`applicationShouldHandleReopen`, normal termination). | Behavior, no key. |
| 33 | Info.plist | Camera and microphone usage strings | Unused boilerplate. | Present | DROP | Owner's scope drops camera and mic. Clack needs no usage strings; Input Monitoring has no Info.plist key. | n/a |

## 2. Clack-only settings the owner asked for (not in Mechvibes)

| Setting | What it does | Default | Decision | Clack key / surface |
|---|---|---|---|---|
| Global mute shortcut | A system-wide hotkey toggles `isMuted`. Mechvibes has no shortcuts at all. It must work while muted, so register it with Carbon `RegisterEventHotKey` (or a key-down monitor that stays on), not through the listen tap that mute tears down. | Unset, or a suggested default (see Q2) | NEW | NEW `muteShortcut` (encoded key code plus modifiers). Settings > General, using a shortcut recorder. |
| Input Monitoring onboarding | One glass sheet explains the permission, has a button that calls `CGRequestListenEventAccess()` and opens Privacy & Security > Input Monitoring, polls `CGPreflightListenEventAccess()` every 1 s and advances when access is granted. It reappears if access is revoked. | Shown until granted | NEW | NEW `hasCompletedOnboarding` (Bool, false). Sheet, plus an inline "Grant Access" banner in the Panel when the permission is missing. |
| Bundled synthesized packs | 4 to 6 original procedural switch sounds (linear, tactile, clicky, thock, typewriter) generated at launch, with deeper space, enter and backspace. | First synthesized pack selected | NEW | Covered by `selectedPackID` (`builtin-<slug>`). No separate key. |
| Default pack for new installs | The fallback when the saved pack is missing. | First built-in pack, chosen quietly | NEW | Behavior, no key. |

## 3. Resulting Settings layout (for build agents)

- **Panel (always visible):** pack picker, volume slider, mute toggle. A permission banner appears only when needed. A small press indicator that respects Reduce Motion.
- **Menu (right-click):** Open Clack, Mute (live checkmark), Random Pack, Reload Packs, Open Custom Packs Folder, Settings..., Quit.
- **Settings > General:** Launch at login, Start hidden (login launches only), Show menu bar icon, Mute shortcut.
- **Settings > Sound:** Play key-up sounds, Play on key auto-repeat, Allow volume above 100%, Keep loudness constant.
- **Settings > Packs:** pack folders list (+ / -), Add Pack..., Reload Packs, Open Custom Packs Folder, Random Pack, and a list of skipped packs with the reason (bad JSON, missing sound file, unsupported version).
- **Settings > About:** app name, version, icon. No links.

## 4. Open questions only the owner can answer

1. **Mechvibes audio already in the project.** `/Users/samuelmittman/clack/Packs/` holds all 12 Mechvibes bundled packs (config.json plus audio converted to .flac/.wav) and `MECHVIBES-LICENSE.txt`, created 2026-10-14 22:12. The build rules say never to copy its audio, and the scope says bundled packs must be original synthesized sounds. Should this folder be deleted, moved outside the project (for example to `~/mechvibes_custom`, so the packs load as Custom packs), or kept on purpose under the MIT license? Nothing has been touched.
2. **Mute shortcut default.** Leave it unset until you record one, or ship a default such as Control+Option+Command+M?
3. **Keep loudness constant.** Do you want this at all? It is Mechvibes v2.3.6's "Active Volume Adjustment", which defaults to on there. The proposal is off by default.
4. **Dock icon.** Show the Dock icon while the window is open and hide it when the window closes (Mechvibes behavior), always run menu-bar-only, or add a "Show Dock icon" toggle?
5. **Volume boost.** Is a 200% ceiling wanted, or is 0 to 100% enough? This decides whether `allowBoost` exists.
6. **Extra pack folders.** Is `~/mechvibes_custom` plus Clack's own Packs folder enough, or should Settings let you add arbitrary folders (which needs security-scoped bookmarks only if the app is ever sandboxed)?
7. **Online install.** Confirm dropping `mechvibes://install` and mechvibes.com downloads entirely, versus a local-only "Add Pack..." flow.
8. **Default volume.** Mechvibes used 20% (v2.3.4) and 50% (v2.3.6). The proposal is 50%. Should your current Mechvibes value (60) be imported on first launch?
