import AVFoundation

enum KeyPhase: Sendable { case down, up }

enum AudioFormat {
    static let sampleRate: Double = 48_000
    /// Every buffer handed to the engine MUST be in this format.
    static let canonical = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false)!
}

/// A loaded, immutable set of sounds. Implementations are final classes marked
/// @unchecked Sendable; buffer(for:phase:) is called on the key-tap thread and must be
/// thread-safe and allocation-light (no decoding, no file IO).
protocol SoundBank: AnyObject, Sendable {
    var packID: String { get }
    var hasKeyUpSounds: Bool { get }
    /// candidates: uiohook scancodes ordered most specific first (from KeyCodeMap).
    /// Returns nil for silence.
    func buffer(for candidates: [Int], phase: KeyPhase) -> AVAudioPCMBuffer?
}

/// Physical key families used for per-key variation (synth) and nothing else.
enum KeyGroup: String, Sendable, CaseIterable {
    case letter, modifier, wide, backspace, enter, space
    init(scancode: Int) {
        switch scancode {
        case 57: self = .space
        case 28, 3612: self = .enter
        case 14: self = .backspace
        case 42, 54, 58, 15: self = .wide                      // shifts, caps lock, tab
        case 1, 29, 3613, 56, 3640, 3675, 3676, 3666,
             59...68, 87, 88, 91...93,
             57416, 57419, 57421, 57424,
             3655, 3657, 3663, 3665, 3667: self = .modifier     // esc, ctrl/alt/cmd/fn, F-keys, arrows, nav
        default: self = .letter
        }
    }
}
