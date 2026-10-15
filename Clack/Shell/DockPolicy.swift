import AppKit

/// Keeps Clack out of the Dock: it lives in the menu bar as an accessory app, even
/// while its main or Settings window is open.
@MainActor
enum DockPolicy {
    private static var observers: [NSObjectProtocol] = []

    static func start() {
        guard observers.isEmpty else { return }
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.willCloseNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
        ]
        let center = NotificationCenter.default
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
                // Next runloop turn, so a closing window is already gone.
                Task { @MainActor in DockPolicy.update() }
            }
            observers.append(token)
        }
        update()
    }

    static func update() {
        // Owner's choice: Clack never shows in the Dock, only in the menu bar.
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
