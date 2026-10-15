import SwiftUI
import AppKit
import Observation

/// A pill-shaped field that records a global shortcut. Escape cancels, Delete clears.
struct ShortcutRecorder: View {
    @Binding private var combo: KeyCombo?
    @State private var session = RecorderSession()

    init(combo: Binding<KeyCombo?>) {
        _combo = combo
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            field
            if session.hasConflict && !session.isRecording {
                Text("Another app is using this shortcut.")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.warning)
            }
        }
        .onAppear { session.refreshConflict() }
        .onDisappear { session.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            session.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            session.stop()
        }
    }

    private var field: some View {
        HStack(spacing: 0) {
            Button {
                if session.isRecording {
                    session.stop()
                } else {
                    session.start { combo = $0 }
                }
            } label: {
                Text(label)
                    .font(DS.Typo.value)
                    .foregroundStyle(combo == nil || session.isRecording ? .secondary : .primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mute shortcut")
            .accessibilityValue(session.isRecording ? "Recording" : (combo?.displayString ?? "None"))
            .accessibilityHint("Records a new shortcut. Press Escape to cancel or Delete to clear.")

            if combo != nil && !session.isRecording {
                Button {
                    combo = nil
                    session.refreshConflict()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Clear shortcut")
                .accessibilityLabel("Clear shortcut")
                .padding(.trailing, 3)
            }
        }
        .frame(width: 170, height: 28)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                .strokeBorder(session.isRecording ? DS.Palette.accent : DS.Palette.hairline,
                              lineWidth: session.isRecording ? 2 : 1)
        )
    }

    private var label: String {
        if session.isRecording { return "Type shortcut…" }
        return combo?.displayString ?? "Record Shortcut"
    }
}

/// Owns the local key monitor so it is always removed and the hot key always resumes.
@MainActor @Observable private final class RecorderSession {
    private(set) var isRecording = false
    private(set) var hasConflict = false

    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var commit: ((KeyCombo?) -> Void)?

    func start(commit: @escaping (KeyCombo?) -> Void) {
        guard !isRecording else { return }
        self.commit = commit
        isRecording = true
        HotKeyCenter.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return consumed ? nil : event
        }
    }

    func stop() {
        guard isRecording else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        commit = nil
        isRecording = false
        HotKeyCenter.shared.resume()
        refreshConflict()
    }

    func refreshConflict() {
        hasConflict = HotKeyCenter.shared.registrationFailed
    }

    private func handle(_ event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case 53: // Escape
            stop()
        case 51, 117: // Delete, Forward Delete
            commit?(nil)
            stop()
        default:
            if let combo = KeyCombo(event: event) {
                commit?(combo)
                stop()
            } else {
                NSSound.beep()
            }
        }
        return true
    }
}
