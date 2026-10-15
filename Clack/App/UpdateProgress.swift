import AppKit
import Observation
import SwiftUI

/// The small "Updating Clack" window: a progress bar while the new version downloads,
/// then "Installing…" until Clack quits and reopens on the new version.
@MainActor @Observable final class UpdateProgress {
    static let shared = UpdateProgress()

    enum Phase: Equatable { case downloading, installing }

    var version = ""
    var fraction = 0.0
    var phase = Phase.downloading
    @ObservationIgnored private var onCancel: (() -> Void)?
    @ObservationIgnored private var panel: NSPanel?

    func begin(version: String, onCancel: @escaping () -> Void) {
        self.version = version
        self.fraction = 0
        self.phase = .downloading
        self.onCancel = onCancel
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 120),
                                styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            panel.title = "Updating Clack"
            panel.titlebarAppearsTransparent = true
            panel.isFloatingPanel = true
            panel.level = .floating
            // Clack is a menu-bar app and usually not frontmost when an update starts,
            // and panels hide on deactivate by default, so keep it visible regardless.
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: UpdateProgressView(progress: self))
            self.panel = panel
        }
        panel?.center()
        panel?.orderFrontRegardless()
    }

    func cancel() {
        onCancel?()
        close()
    }

    func close() {
        panel?.orderOut(nil)
    }
}

private struct UpdateProgressView: View {
    let progress: UpdateProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(progress.phase == .downloading
                 ? "Downloading Clack \(progress.version)…"
                 : "Installing. Clack will reopen in a moment.")
                .font(.system(size: 13, weight: .semibold))
            if progress.phase == .downloading {
                ProgressView(value: progress.fraction)
                HStack {
                    Text("\(Int(progress.fraction * 100))%")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer()
                    Button("Cancel") { progress.cancel() }
                        .controlSize(.small)
                }
            } else {
                ProgressView().progressViewStyle(.linear)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 30)
        .padding(.bottom, 16)
        .frame(width: 340)
    }
}
