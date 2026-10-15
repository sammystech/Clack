import AppKit
import Observation

/// Menu bar item: left-click opens the glass panel, right-click (or Control-click)
/// opens a native menu rebuilt on every open so its state is always accurate.
@MainActor
final class StatusItemController: NSObject {
    private let model: AppModel
    private var item: NSStatusItem?
    private lazy var panel = MenuBarPanel()

    init(model: AppModel) {
        self.model = model
        super.init()
        apply()
        observe()
    }

    // MARK: State sync

    private func observe() {
        withObservationTracking {
            _ = model.listeningStatus
            _ = model.preferences.showMenuBarIcon
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.apply()
                self?.observe()
            }
        }
    }

    private func apply() {
        guard model.preferences.showMenuBarIcon else {
            if item != nil {
                panel.dismiss()
                if let item { NSStatusBar.system.removeStatusItem(item) }
                item = nil
            }
            return
        }
        if item == nil { install() }
        updateIcon()
    }

    private func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.toolTip = "Clack"
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        self.item = item
    }

    private func updateIcon() {
        guard let button = item?.button else { return }
        let status = model.listeningStatus
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let name = status == .noAccess ? "keyboard.badge.exclamationmark" : "keyboard"
        let base = NSImage(systemSymbolName: name, accessibilityDescription: "Clack")
            ?? NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Clack")
        let image = base?.withSymbolConfiguration(config) ?? base
        image?.isTemplate = true
        button.image = image
        button.appearsDisabled = (status == .muted)
    }

    // MARK: Clicks

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            panel.toggle(relativeTo: sender)
        }
    }

    private func showMenu() {
        guard let item, let button = item.button else { return }
        panel.dismiss()

        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(makeItem("Open Clack", symbol: "macwindow", action: #selector(openClack)))
        menu.addItem(.separator())

        let mute = makeItem("Mute", symbol: "speaker.slash", action: #selector(toggleMute))
        mute.state = model.preferences.isMuted ? .on : .off
        if let equivalent = model.preferences.muteShortcut?.menuKeyEquivalent, equivalent.0.count == 1 {
            // Display only: the global hotkey does the real work.
            mute.keyEquivalent = equivalent.0.lowercased()
            mute.keyEquivalentModifierMask = equivalent.1
        }
        menu.addItem(mute)

        let random = makeItem("Random Pack", symbol: "shuffle", action: #selector(randomPack))
        random.isEnabled = model.canRandomize
        menu.addItem(random)
        menu.addItem(makeItem("Reload Packs", symbol: "arrow.clockwise", action: #selector(reloadPacks)))
        menu.addItem(makeItem("Open Custom Packs Folder", symbol: "folder", action: #selector(openPacksFolder)))
        menu.addItem(.separator())

        let settings = makeItem("Settings…", symbol: "gearshape", action: #selector(openSettings))
        settings.keyEquivalent = ","
        settings.keyEquivalentModifierMask = [.command]
        menu.addItem(settings)
        menu.addItem(.separator())

        let quit = makeItem("Quit Clack", symbol: "power", action: #selector(quit))
        quit.keyEquivalent = "q"
        quit.keyEquivalentModifierMask = [.command]
        menu.addItem(quit)

        item.menu = menu
        button.performClick(nil)
        item.menu = nil
    }

    private func makeItem(_ title: String, symbol: String, action: Selector) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        menuItem.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return menuItem
    }

    // MARK: Menu actions

    @objc private func openClack() { MainWindowController.shared.show() }
    @objc private func toggleMute() { model.toggleMute() }
    @objc private func randomPack() { model.randomPack() }
    @objc private func reloadPacks() { model.reloadPacks() }
    @objc private func openPacksFolder() { model.openCustomPacksFolder() }
    @objc private func openSettings() { SettingsOpener.open() }
    @objc private func quit() { NSApp.terminate(nil) }
}
