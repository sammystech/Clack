import AppKit

/// Settings live on Clack's main page; "Settings…" (⌘, and the menu bar) just opens it.
@MainActor
enum SettingsOpener {
    static func open() {
        MainWindowController.shared.show()
    }
}
