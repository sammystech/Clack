import AppKit

/// Opens the SwiftUI Settings scene from AppKit code (menu bar menu, panel).
@MainActor
enum SettingsOpener {
    static func open() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        if let appMenu = NSApp.mainMenu?.items.first?.submenu,
           let index = appMenu.items.firstIndex(where: { $0.keyEquivalent == "," }) {
            appMenu.performActionForItem(at: index)
        } else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            DockPolicy.update()
        }
    }
}
