import Observation

/// Drives the keycap: true while at least one key is held (v2.3.6 rule).
@MainActor @Observable final class KeyActivity {
    private(set) var isPressed = false

    func set(_ pressed: Bool) {
        if isPressed != pressed { isPressed = pressed }
    }
}
