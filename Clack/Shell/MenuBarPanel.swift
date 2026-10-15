import AppKit
import SwiftUI

/// Closes the menu bar panel from inside its SwiftUI content.
private struct CloseMenuBarPanelKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable () -> Void = {}
}

extension EnvironmentValues {
    var closeMenuBarPanel: @MainActor @Sendable () -> Void {
        get { self[CloseMenuBarPanelKey.self] }
        set { self[CloseMenuBarPanelKey.self] = newValue }
    }
}

/// Borderless, non-activating glass panel shown under the status item on left-click.
/// It never steals focus from the frontmost app.
final class MenuBarPanel: NSPanel, NSWindowDelegate {
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private var generation = 0
    private var anchorTop: CGFloat?
    private var lastDismissal = Date.distantPast
    private var isDismissing = false

    convenience init() {
        self.init(contentRect: .zero,
                  styleMask: [.borderless, .nonactivatingPanel],
                  backing: .buffered,
                  defer: true)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = hostingView
        delegate = self
        installRoot()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        dismiss()
    }

    // MARK: Presentation

    func toggle(relativeTo button: NSStatusBarButton) {
        if isVisible && !isDismissing {
            dismiss()
        } else if Date().timeIntervalSince(lastDismissal) > 0.25 {
            // The click that made us resign key also lands here; don't reopen on it.
            show(relativeTo: button)
        }
    }

    func show(relativeTo button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        isDismissing = false
        installRoot()   // fresh SwiftUI state so the appear animation runs every time
        hostingView.layoutSubtreeIfNeeded()

        var size = hostingView.fittingSize
        size.width = DS.Size.menuPanelWidth

        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? buttonFrame
        var x = buttonFrame.midX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - 8 - size.width)
        let top = buttonFrame.minY - 6
        anchorTop = top

        setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: false)
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        invalidateShadow()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
        }
    }

    func dismiss() {
        guard isVisible, !isDismissing else { return }
        isDismissing = true
        lastDismissal = Date()
        let token = generation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, self.isDismissing else { return }
                self.orderOut(nil)
                self.alphaValue = 1
                self.isDismissing = false
            }
        })
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        dismiss()
    }

    /// Content height changes (banner appearing, packs loading) keep the top edge pinned
    /// under the status item instead of growing upward into the menu bar.
    func windowDidResize(_ notification: Notification) {
        guard let anchorTop, abs(frame.maxY - anchorTop) > 0.5 else { return }
        setFrameOrigin(NSPoint(x: frame.minX, y: anchorTop - frame.height))
        invalidateShadow()
    }

    // MARK: Content

    private func installRoot() {
        generation += 1
        let root = MenuBarPanelView()
            .environment(AppModel.shared)
            .environment(\.closeMenuBarPanel) { [weak self] in self?.dismiss() }
            .id(generation)
        hostingView.rootView = AnyView(root)
    }
}
