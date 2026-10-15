import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import os

/// Low-latency playback. handle(_:) runs on the key-tap thread: it picks a buffer from the
/// active bank and schedules it on a pooled player. The lock only guards state; buffer
/// lookup and scheduling happen outside it.
///
/// Graph: 24 voices -> voiceMixer -> EQ (boost gain) -> PeakLimiter -> mainMixer -> output.
final class SoundEngine: @unchecked Sendable {
    struct Config: Sendable {
        var playOnAutoRepeat: Bool
        var playKeyUpSounds: Bool
    }

    enum Transition { case pressed, released }

    private struct State {
        var bank: (any SoundBank)?
        var config = Config(playOnAutoRepeat: false, playKeyUpSounds: true)
        var down: Set<UInt16> = []
        var nextVoice = 0
        var lastPlay: UInt64 = 0
        var audioPaused = true
        var rebuilding = false
    }

    private static let voiceCount = 24
    private static let capsLockKeyCode: UInt16 = 0x39
    private static let previewScancode = 30
    private static let capsLockUpDelay = 0.06
    private static let previewUpDelay = 0.09
    private static let idleSuspendNanos: UInt64 = 30_000_000_000
    private static let idleCheckInterval: TimeInterval = 10

    private let engine = AVAudioEngine()
    private let voices: [AVAudioPlayerNode]
    private let voiceMixer = AVAudioMixerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 1)
    private let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: kAudioUnitSubType_PeakLimiter,
        componentManufacturer: kAudioUnitManufacturer_Apple,
        componentFlags: 0,
        componentFlagsMask: 0))

    private let state = OSAllocatedUnfairLock(uncheckedState: State())
    /// Serializes engine start/pause/stop/rebuild across the main and tap threads.
    private let control = NSLock()
    private var idleTimer: Timer?
    private var configObserver: NSObjectProtocol?

    init() {
        voices = (0..<Self.voiceCount).map { _ in AVAudioPlayerNode() }
        eq.bands[0].bypass = true
        eq.globalGain = 0
        engine.attach(voiceMixer)
        engine.attach(eq)
        engine.attach(limiter)
        voices.forEach { engine.attach($0) }
        connectGraph()
    }

    deinit {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
    }

    // MARK: - Lifecycle (main thread)

    func start() throws {
        if configObserver == nil {
            configObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
            ) { [weak self] _ in
                self?.rebuildAfterConfigurationChange()
            }
        }
        startIdleTimer()
        state.withLockUnchecked { $0.lastPlay = Self.now() }

        control.lock()
        defer { control.unlock() }
        requestSmallIOBuffer()
        engine.prepare()
        do {
            try engine.start()
        } catch {
            // Stay paused; the next key press retries.
            state.withLockUnchecked { $0.audioPaused = true }
            throw error
        }
        voices.forEach { $0.play() }
        state.withLockUnchecked { $0.audioPaused = false }
    }

    func shutdown() {
        idleTimer?.invalidate()
        idleTimer = nil
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
            self.configObserver = nil
        }
        control.lock()
        engine.stop()
        state.withLockUnchecked { $0.audioPaused = true }
        control.unlock()
    }

    func pauseAudio() {
        control.lock()
        defer { control.unlock() }
        let alreadyPaused = state.withLockUnchecked { s -> Bool in
            let was = s.audioPaused
            s.audioPaused = true
            return was
        }
        if !alreadyPaused { engine.pause() }
    }

    func setBank(_ bank: (any SoundBank)?) {
        // The old bank is released after the swap; in-flight buffers are retained by the players.
        let old = state.withLockUnchecked { s -> (any SoundBank)? in
            let previous = s.bank
            s.bank = bank
            return previous
        }
        _ = old
    }

    func updateConfig(_ c: Config) {
        state.withLockUnchecked { $0.config = c }
    }

    /// Linear gain. Up to 1 it is mixer volume; above 1 the EQ adds up to +24 dB and the
    /// limiter after it keeps peaks in check.
    func setGain(_ g: Double) {
        let gain = max(0, g)
        if gain <= 1 {
            voiceMixer.outputVolume = Float(gain)
            eq.globalGain = 0
        } else {
            voiceMixer.outputVolume = 1
            eq.globalGain = Float(min(24, 20 * log10(gain)))
        }
    }

    func resetHeldKeys() {
        state.withLockUnchecked { $0.down.removeAll() }
    }

    /// True while any key is in the held set (used to time the Caps Lock keycap release).
    var hasHeldKeys: Bool {
        state.withLockUnchecked { !$0.down.isEmpty }
    }

    // MARK: - Tap thread

    func handle(_ e: KeyEvent) -> Transition? {
        let code = e.keyCode
        switch e.kind {
        case .down:
            return keyDown(code, isAutorepeat: e.isAutorepeat)
        case .up:
            return keyUp(code)
        case .flagsChanged:
            if code == Self.capsLockKeyCode {
                return capsLock()
            }
            let isDown: Bool
            if let mask = KeyCodeMap.modifierMask(forKeyCode: code) {
                isDown = (e.flags & mask) != 0
            } else {
                isDown = !state.withLockUnchecked { $0.down.contains(code) }
            }
            if isDown {
                return modifierDown(code)
            }
            return keyUp(code)
        }
    }

    func preview() {
        let candidates = [Self.previewScancode]
        play(candidates, .down)
        if wantsKeyUp() {
            DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + Self.previewUpDelay) { [self] in
                self.play(candidates, .up)
            }
        }
    }

    private func keyDown(_ code: UInt16, isAutorepeat: Bool) -> Transition? {
        let wasEmpty: Bool? = state.withLockUnchecked { s in
            if !s.config.playOnAutoRepeat && (isAutorepeat || s.down.contains(code)) { return nil }
            let empty = s.down.isEmpty
            s.down.insert(code)
            return empty
        }
        guard let wasEmpty else { return nil }
        play(KeyCodeMap.candidates(forKeyCode: code), .down)
        return wasEmpty ? .pressed : nil
    }

    /// A modifier press. Autorepeat never applies; a duplicate press for a held modifier is ignored.
    private func modifierDown(_ code: UInt16) -> Transition? {
        let wasEmpty: Bool? = state.withLockUnchecked { s in
            if s.down.contains(code) { return nil }
            let empty = s.down.isEmpty
            s.down.insert(code)
            return empty
        }
        guard let wasEmpty else { return nil }
        play(KeyCodeMap.candidates(forKeyCode: code), .down)
        return wasEmpty ? .pressed : nil
    }

    private func keyUp(_ code: UInt16) -> Transition? {
        let (nowEmpty, playUp): (Bool, Bool) = state.withLockUnchecked { s in
            s.down.remove(code)
            return (s.down.isEmpty, s.config.playKeyUpSounds && (s.bank?.hasKeyUpSounds ?? false))
        }
        if playUp {
            play(KeyCodeMap.candidates(forKeyCode: code), .up)
        }
        return nowEmpty ? .released : nil
    }

    /// Every Caps Lock flagsChanged is a press; its key-up sound follows 0.06 s later.
    /// The caller schedules the keycap release.
    private func capsLock() -> Transition? {
        let candidates = KeyCodeMap.candidates(forKeyCode: Self.capsLockKeyCode)
        play(candidates, .down)
        if wantsKeyUp() {
            DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + Self.capsLockUpDelay) { [self] in
                self.play(candidates, .up)
            }
        }
        return hasHeldKeys ? nil : .pressed
    }

    private func wantsKeyUp() -> Bool {
        state.withLockUnchecked { s in
            s.config.playKeyUpSounds && (s.bank?.hasKeyUpSounds ?? false)
        }
    }

    private func play(_ candidates: [Int], _ phase: KeyPhase) {
        guard !candidates.isEmpty else { return }
        let bank: (any SoundBank)? = state.withLockUnchecked { s in
            s.rebuilding ? nil : s.bank
        }
        guard let bank, let buffer = bank.buffer(for: candidates, phase: phase) else { return }
        // A buffer in any other format would raise an exception inside AVFoundation.
        let format = buffer.format
        guard buffer.frameLength > 0,
              format.channelCount == AudioFormat.canonical.channelCount,
              format.sampleRate == AudioFormat.sampleRate,
              format.commonFormat == .pcmFormatFloat32,
              !format.isInterleaved else { return }

        let (voiceIndex, needsStart): (Int, Bool) = state.withLockUnchecked { s in
            let index = s.nextVoice
            s.nextVoice = (index + 1) % Self.voiceCount
            s.lastPlay = Self.now()
            return (index, s.audioPaused)
        }
        if needsStart && !resumeAudio() { return }
        voices[voiceIndex].scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
    }

    /// Restarts the engine after an idle suspend, a mute or a failed start. Returns false if
    /// the engine still cannot run (the next key press tries again).
    private func resumeAudio() -> Bool {
        control.lock()
        defer { control.unlock() }
        let paused = state.withLockUnchecked { $0.audioPaused }
        guard paused else { return true }
        do {
            try engine.start()
        } catch {
            Log.audio.error("Audio engine failed to start: \(error.localizedDescription, privacy: .public)")
            return false
        }
        voices.forEach { $0.play() }
        state.withLockUnchecked { $0.audioPaused = false }
        return true
    }

    // MARK: - Graph

    private func connectGraph() {
        let format = AudioFormat.canonical
        for (index, voice) in voices.enumerated() {
            engine.connect(voice, to: voiceMixer, fromBus: 0, toBus: index, format: format)
        }
        engine.connect(voiceMixer, to: eq, format: format)
        engine.connect(eq, to: limiter, format: format)
        engine.connect(limiter, to: engine.mainMixerNode, format: format)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
    }

    /// Output device or sample-rate change: rebuild and restart, keeping bank and gain.
    private func rebuildAfterConfigurationChange() {
        control.lock()
        defer { control.unlock() }
        state.withLockUnchecked { $0.rebuilding = true }
        defer { state.withLockUnchecked { $0.rebuilding = false } }

        engine.stop()
        connectGraph()
        requestSmallIOBuffer()
        engine.prepare()
        do {
            try engine.start()
            voices.forEach { $0.play() }
            state.withLockUnchecked { $0.audioPaused = false; $0.lastPlay = Self.now() }
            Log.audio.info("Audio graph rebuilt after a configuration change")
        } catch {
            state.withLockUnchecked { $0.audioPaused = true }
            Log.audio.error("Audio engine restart failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func requestSmallIOBuffer() {
        guard let unit = engine.outputNode.audioUnit else { return }
        var frames: UInt32 = 256
        _ = AudioUnitSetProperty(
            unit, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0,
            &frames, UInt32(MemoryLayout<UInt32>.size))
    }

    // MARK: - Idle suspend (Howler autoSuspend parity)

    private func startIdleTimer() {
        guard idleTimer == nil else { return }
        let timer = Timer(timeInterval: Self.idleCheckInterval, repeats: true) { [weak self] _ in
            self?.suspendIfIdle()
        }
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    private func suspendIfIdle() {
        let idle = state.withLockUnchecked { s in
            !s.audioPaused && Self.now() &- s.lastPlay > Self.idleSuspendNanos
        }
        if idle { pauseAudio() }
    }

    private static func now() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }
}
