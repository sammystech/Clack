import Observation

/// Drives the keycap: true while at least one key is held (v2.3.6 rule).
@MainActor @Observable final class KeyActivity {
    private(set) var isPressed = false
    /// Label of the most recent key press, shown on the keycap; cleared after a short pause.
    private(set) var lastKey: String?
    private var clearTask: Task<Void, Never>?

    func set(_ pressed: Bool) {
        if isPressed != pressed { isPressed = pressed }
    }

    func show(_ label: String) {
        lastKey = label
        clearTask?.cancel()
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            self?.lastKey = nil
        }
    }
}
