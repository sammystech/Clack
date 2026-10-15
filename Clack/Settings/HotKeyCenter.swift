import AppKit
import Carbon.HIToolbox

/// The global mute shortcut, registered through Carbon so it works without Input Monitoring
/// and while the event tap is removed (muted).
@MainActor final class HotKeyCenter {
    static let shared = HotKeyCenter()

    /// True when the last attempt to register the current combo failed (usually because
    /// another app owns it). Read by ShortcutRecorder to show an inline warning.
    private(set) var registrationFailed = false

    private var handlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var combo: KeyCombo?
    private var handler: (@MainActor () -> Void)?
    private var isSuspended = false

    private static let signature: OSType = 0x434C414B // 'CLAK'

    private init() {}

    /// Replaces the current shortcut. Passing nil just clears it. Returns false when macOS
    /// refuses the combo. While suspended the combo is stored and registered on resume().
    @discardableResult
    func register(_ combo: KeyCombo?, handler: @escaping @MainActor () -> Void) -> Bool {
        installHandlerIfNeeded()
        unregisterCurrent()
        self.combo = combo
        self.handler = handler
        guard !isSuspended else { return true }
        return registerCurrent()
    }

    /// Temporarily unregisters the shortcut (while the recorder listens for a new one).
    func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        unregisterCurrent()
    }

    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        registerCurrent()
    }

    fileprivate func fire() {
        handler?()
    }

    // MARK: - Private

    @discardableResult
    private func registerCurrent() -> Bool {
        unregisterCurrent()
        guard let combo else {
            registrationFailed = false
            return true
        }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: 1),
            GetApplicationEventTarget(),
            0,
            &ref)
        if status == noErr {
            hotKeyRef = ref
            registrationFailed = false
            return true
        }
        hotKeyRef = nil
        registrationFailed = true
        Log.input.error("Could not register the mute shortcut (status \(status, privacy: .public))")
        return false
    }

    private func unregisterCurrent() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ -> OSStatus in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { HotKeyCenter.shared.fire() }
                }
                return noErr
            },
            1,
            &spec,
            nil,
            &handlerRef)
        if status != noErr {
            Log.input.error("Could not install the hot key handler (status \(status, privacy: .public))")
        }
    }
}
