import AppKit
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private var launchedAtLogin = false
    private var isDuplicateInstance = false
    private var powerOffObserver: NSObjectProtocol?

    // MARK: Launch

    func applicationWillFinishLaunching(_ notification: Notification) {
        launchedAtLogin = Self.detectLaunchedAtLogin()

        let bundleID = Bundle.main.bundleIdentifier ?? "com.samuelmittman.Clack"
        let myPID = ProcessInfo.processInfo.processIdentifier
        func otherInstances() -> [NSRunningApplication] {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != myPID && !$0.isTerminated }
        }

        // After "Relaunch", wait (up to 3 s) for the previous instance to exit.
        if CommandLine.arguments.contains("--relaunch") {
            let deadline = Date().addingTimeInterval(3.0)
            while !otherInstances().isEmpty && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
        }

        // Single instance: hand off to the running copy and quit.
        if let other = otherInstances().first {
            isDuplicateInstance = true
            other.activate()
            NSApp.terminate(nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isDuplicateInstance else { return }

        // Route quit requests (System Settings' "Quit & Reopen", Activity Monitor, scripts)
        // through quitClosingSheets so an open onboarding sheet can't block them.
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleQuitEvent(_:withReply:)),
            forEventClass: AEEventClass(kCoreEventClass), andEventID: AEEventID(kAEQuitApplication))

        let model = AppModel.shared
        model.requestMainWindow = { MainWindowController.shared.show() }
        model.start()
        statusItemController = StatusItemController(model: model)
        DockPolicy.start()
        Updater.shared.startBackgroundChecks()
        if UserDefaults.standard.bool(forKey: "speakKeys") { KeySpeaker.shared.prepare() }
        #if DEBUG
        if CommandLine.arguments.contains("--preview-update-ui") {
            UpdateProgress.shared.begin(version: "9.9") {}
            UpdateProgress.shared.fraction = 0.42
        }
        if CommandLine.arguments.contains("--check-inline") {
            Updater.shared.checkInline()
        }
        #endif

        powerOffObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { NSApp.terminate(nil) }
        }

        // Never start invisible without a menu bar icon or while onboarding is pending.
        let prefs = model.preferences
        let stayHidden = prefs.startHidden
            && LaunchAtLogin.isEnabled
            && launchedAtLogin
            && prefs.showMenuBarIcon
            && !model.showOnboarding
        if !stayHidden {
            MainWindowController.shared.show()
        }
    }

    // MARK: Lifecycle

    /// Recovery path when the menu bar icon is hidden: opening Clack again shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !isDuplicateInstance else { return false }
        MainWindowController.shared.show()
        return false
    }

    @objc private func handleQuitEvent(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        AppModel.shared.quitClosingSheets()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !isDuplicateInstance else { return }
        AppModel.shared.shutdown()
    }

    // MARK: Helpers

    private static func detectLaunchedAtLogin() -> Bool {
        if let event = NSAppleEventManager.shared().currentAppleEvent,
           event.eventID == AEEventID(kAEOpenApplication),
           event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem) {
            return true
        }
        // Fresh boot heuristic (SMAppService login items do not always set the event).
        return ProcessInfo.processInfo.systemUptime < 300
    }
}
