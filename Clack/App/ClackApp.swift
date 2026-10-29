import SwiftUI

@main
struct ClackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Settings are part of the main window; this scene only carries the menu commands.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { SettingsOpener.open() }
                    .keyboardShortcut(",")
            }
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Updater.shared.checkNow() }
            }
        }
    }
}
