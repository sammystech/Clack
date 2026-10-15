import AppKit

/// Shows the Dock icon only while a real Clack window (main or Settings) is open or
/// minimized; otherwise Clack lives in the menu bar as an accessory app.
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
        let hasWindow = NSApp.windows.contains { window in
            !(window is NSPanel)
                && window.styleMask.contains(.titled)
                && (window.isVisible || window.isMiniaturized)
        }
        let wanted: NSApplication.ActivationPolicy = hasWindow ? .regular : .accessory
        if NSApp.activationPolicy() != wanted {
            NSApp.setActivationPolicy(wanted)
        }
    }
}
