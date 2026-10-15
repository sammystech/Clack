import AppKit
import CoreGraphics
import Foundation
import os

/// One keyboard event from the tap. Carries only what the engine needs; never logged.
struct KeyEvent: Sendable {
    enum Kind: Sendable { case down, up, flagsChanged }
    let keyCode: UInt16
    let kind: Kind
    let isAutorepeat: Bool
    let flags: UInt64
}

/// Listen-only CGEventTap on a dedicated thread with its own run loop. The handler is
/// called synchronously on that thread for every key event, so it must be fast.
/// Secure input (password fields) simply delivers no events.
final class KeyMonitor: @unchecked Sendable {
    private struct State {
        var tap: CFMachPort?
        var runLoop: CFRunLoop?
        var running = false
        var generation = 0
        var startResult = false
    }

    private let handler: @Sendable (KeyEvent) -> Void
    private let state = OSAllocatedUnfairLock(uncheckedState: State())

    init(handler: @escaping @Sendable (KeyEvent) -> Void) {
        self.handler = handler
    }

    var isRunning: Bool {
        state.withLockUnchecked { $0.running }
    }

    /// Installs the tap. Returns false when the tap cannot be created (no Input Monitoring
    /// access) or the thread did not come up within 1 s.
    func start() -> Bool {
        let generation: Int? = state.withLockUnchecked { s in
            if s.running { return nil }
            s.generation &+= 1
            s.startResult = false
            return s.generation
        }
        guard let generation else { return true }

        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            self.runTap(generation: generation, ready: ready)
        }
        thread.qualityOfService = .userInteractive
        thread.name = "Clack.KeyTap"
        thread.start()

        if ready.wait(timeout: .now() + 1.0) == .timedOut {
            // Cancel this attempt; the thread tears itself down if it gets going later.
            state.withLockUnchecked { s in
                if s.generation == generation { s.generation &+= 1 }
            }
            Log.input.error("Event tap thread did not start in time")
            return false
        }
        return state.withLockUnchecked { $0.startResult }
    }

    func stop() {
        let (tap, runLoop): (CFMachPort?, CFRunLoop?) = state.withLockUnchecked { s in
            let pair = (s.tap, s.runLoop)
            s.tap = nil
            s.runLoop = nil
            s.running = false
            s.generation &+= 1
            return pair
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoop {
            CFRunLoopStop(runLoop)
        }
    }

    // MARK: - Tap thread

    private func runTap(generation: Int, ready: DispatchSemaphore) {
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << KeyMonitor.systemDefinedType)   // brightness, volume, media keys

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                if let userInfo {
                    Unmanaged<KeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                        .process(type: type, event: event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            state.withLockUnchecked { s in
                if s.generation == generation { s.startResult = false }
            }
            ready.signal()
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            ready.signal()
            return
        }
        let runLoop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(runLoop, source, .commonModes)

        let accepted: Bool = state.withLockUnchecked { s in
            guard s.generation == generation else { return false }
            s.tap = tap
            s.runLoop = runLoop
            s.running = true
            s.startResult = true
            return true
        }
        guard accepted else {
            // start() timed out or stop() ran meanwhile: tear down quietly.
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFMachPortInvalidate(tap)
            ready.signal()
            return
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        ready.signal()
        CFRunLoopRun()
        CFRunLoopRemoveSource(runLoop, source, .commonModes)
    }

    /// NX_SYSDEFINED: the top-row brightness, volume, media and keyboard-light keys.
    private static let systemDefinedType: UInt32 = 14

    /// NX_KEYTYPE_* -> the Mac F-key code whose pack slot it plays (F1...F12 layout).
    private static let auxKeyCodes: [Int: UInt16] = [
        3: 0x7A, 2: 0x78,                       // brightness down/up: F1, F2
        22: 0x60, 21: 0x61, 23: 0x61,           // keyboard light down/up/toggle: F5, F6
        20: 0x62, 18: 0x62,                     // rewind/previous: F7
        16: 0x64,                               // play/pause: F8
        19: 0x65, 17: 0x65,                     // fast/next: F9
        7: 0x6D, 1: 0x67, 0: 0x6F,              // mute, volume down/up: F10, F11, F12
    ]

    /// Real presses from a keyboard arrive from the HID system with no sending process.
    /// Anything a program injects (scripts, AI or auto typers, remote control) carries that
    /// program's PID, even when it claims the HID state, so it never plays a sound.
    private static func isPhysical(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUnixProcessID) == 0
    }

    private func processSystemDefined(_ event: CGEvent) {
        guard Self.isPhysical(event) else { return }
        guard let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else { return }
        let data1 = ns.data1
        let keyType = (data1 & 0xFFFF0000) >> 16
        let keyFlags = data1 & 0xFFFF
        let keyState = (keyFlags & 0xFF00) >> 8
        guard let keyCode = Self.auxKeyCodes[keyType], keyState == 0xA || keyState == 0xB else { return }
        handler(KeyEvent(keyCode: keyCode,
                         kind: keyState == 0xA ? .down : .up,
                         isAutorepeat: keyFlags & 0x1 != 0,
                         flags: event.flags.rawValue))
    }

    private func process(type: CGEventType, event: CGEvent) {
        let kind: KeyEvent.Kind
        switch type {
        case .keyDown: kind = .down
        case .keyUp: kind = .up
        case .flagsChanged: kind = .flagsChanged
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap = state.withLockUnchecked({ $0.tap }) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        default:
            if type.rawValue == Self.systemDefinedType { processSystemDefined(event) }
            return
        }
        guard Self.isPhysical(event) else { return }
        let keyEvent = KeyEvent(
            keyCode: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)),
            kind: kind,
            isAutorepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            flags: event.flags.rawValue
        )
        handler(keyEvent)
    }
}
