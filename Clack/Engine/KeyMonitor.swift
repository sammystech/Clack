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
            return
        }
        let keyEvent = KeyEvent(
            keyCode: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)),
            kind: kind,
            isAutorepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            flags: event.flags.rawValue
        )
        handler(keyEvent)
    }
}
