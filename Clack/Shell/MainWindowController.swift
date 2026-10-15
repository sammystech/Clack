import AppKit
import SwiftUI

/// Owns Clack's single main window. Closing (red button, Cmd+W) hides it; Clack keeps
/// running in the menu bar.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()

    private static let autosaveName = "ClackMainWindow"
    private var window: NSWindow?

    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        let window = makeWindowIfNeeded()
        NSApp.setActivationPolicy(.regular)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        DockPolicy.update()
    }

    func hide() {
        window?.orderOut(nil)
        DockPolicy.update()
    }

    func toggle() {
        if let window, window.isVisible, window.isKeyWindow, NSApp.isActive {
            hide()
        } else {
            show()
        }
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    // MARK: Building

    private func makeWindowIfNeeded() -> NSWindow {
        if let window { return window }

        let hosting = NSHostingController(rootView: MainView().environment(AppModel.shared))
        hosting.sceneBridgingOptions = [.toolbars]
        hosting.sizingOptions = []   // the window owns its size; SwiftUI fills it

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: DS.Size.mainWindow),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.contentViewController = hosting
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "Clack"
        window.toolbarStyle = .unified
        window.setContentSize(DS.Size.mainWindow)
        window.contentMinSize = DS.Size.mainWindowMin
        window.contentMaxSize = DS.Size.mainWindowMax
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.fullScreenNone)
        window.delegate = self
        if !window.setFrameUsingName(Self.autosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.autosaveName)

        self.window = window
        return window
    }
}
