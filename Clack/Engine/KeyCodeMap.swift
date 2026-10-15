import Foundation

/// macOS virtual key codes (kVK_*) to libuiohook standard scancodes, the key space
/// Mechvibes packs use. All tables are precomputed so the tap thread only does lookups.
enum KeyCodeMap {
    /// Primary scancode per kVK. Includes the Mac position swap for Command/Option
    /// (left Command plays the pack's left Alt slot, and so on) and JIS extras as a generic letter.
    private static let base: [UInt16: Int] = [
        0x00: 30, 0x01: 31, 0x02: 32, 0x03: 33, 0x04: 35, 0x05: 34, 0x06: 44, 0x07: 45,
        0x08: 46, 0x09: 47, 0x0A: 41, 0x0B: 48, 0x0C: 16, 0x0D: 17, 0x0E: 18, 0x0F: 19,
        0x10: 21, 0x11: 20, 0x12: 2, 0x13: 3, 0x14: 4, 0x15: 5, 0x16: 7, 0x17: 6,
        0x18: 13, 0x19: 10, 0x1A: 8, 0x1B: 12, 0x1C: 9, 0x1D: 11, 0x1E: 27, 0x1F: 24,
        0x20: 22, 0x21: 26, 0x22: 23, 0x23: 25, 0x24: 28, 0x25: 38, 0x26: 36, 0x27: 40,
        0x28: 37, 0x29: 39, 0x2A: 43, 0x2B: 51, 0x2C: 53, 0x2D: 49, 0x2E: 50, 0x2F: 52,
        0x30: 15, 0x31: 57, 0x32: 41, 0x33: 14, 0x35: 1, 0x38: 42, 0x39: 58, 0x3B: 29,
        0x3C: 54, 0x3E: 3613, 0x41: 83, 0x43: 55, 0x45: 78, 0x47: 69, 0x4B: 3637, 0x4C: 3612,
        0x4E: 74, 0x51: 3597, 0x52: 82, 0x53: 79, 0x54: 80, 0x55: 81, 0x56: 75, 0x57: 76,
        0x58: 77, 0x59: 71, 0x5B: 72, 0x5C: 73, 0x7A: 59, 0x78: 60, 0x63: 61, 0x76: 62,
        0x60: 63, 0x61: 64, 0x62: 65, 0x64: 66, 0x65: 67, 0x6D: 68, 0x67: 87, 0x6F: 88,
        0x69: 91, 0x6B: 92, 0x71: 93, 0x72: 3666, 0x73: 3655, 0x74: 3657, 0x75: 3667, 0x77: 3663,
        0x79: 3665, 0x7B: 57419, 0x7C: 57421, 0x7D: 57424, 0x7E: 57416, 0x3F: 3666,
        // Mac position swap (per side): Command -> Alt slot, Option -> Meta slot.
        0x37: 56, 0x36: 3640, 0x3A: 3675, 0x3D: 3676,
        // Top-row specials on newer Macs play their F-key slot: Launchpad and Spotlight F4,
        // Mission Control F3, Dictation F5, Do Not Disturb F6.
        0x83: 62, 0xA0: 61, 0xB1: 62, 0xB0: 63, 0xB2: 64,
        // JIS extras (Eisu, Kana, Yen, underscore, keypad comma) play as a generic letter.
        0x5D: 30, 0x5E: 30, 0x5F: 30, 0x66: 30, 0x68: 30,
    ]

    /// Fallback chain per primary scancode, for packs that lack the specific key.
    private static let fallbacks: [Int: [Int]] = [
        56: [3640], 3640: [56], 3675: [3676], 3676: [3675],
        29: [3613], 3613: [29], 42: [54], 54: [42],
        3612: [28], 3597: [69, 13], 3667: [14],
        91: [88], 92: [88], 93: [88],
        // F-keys (and the media keys that play as them) fall back to Escape, same row.
        59: [1], 60: [1], 61: [1], 62: [1], 63: [1], 64: [1],
        65: [1], 66: [1], 67: [1], 68: [1], 87: [1], 88: [1],
        // Keypad to main row for packs without a numpad.
        79: [2], 80: [3], 81: [4], 75: [5], 76: [6], 77: [7], 71: [8], 72: [9], 73: [10],
        82: [11], 83: [52], 74: [12], 78: [13], 55: [9], 3637: [53], 69: [1],
    ]

    private static let candidateTable: [UInt16: [Int]] = {
        var table: [UInt16: [Int]] = [:]
        table.reserveCapacity(base.count)
        for (keyCode, scancode) in base {
            table[keyCode] = [scancode] + (fallbacks[scancode] ?? [])
        }
        return table
    }()

    /// Device-dependent NX modifier masks used to tell press from release in flagsChanged.
    private static let modifierMasks: [UInt16: UInt64] = [
        0x3B: 0x1,       // left Control
        0x38: 0x2,       // left Shift
        0x3C: 0x4,       // right Shift
        0x37: 0x8,       // left Command
        0x36: 0x10,      // right Command
        0x3A: 0x20,      // left Option
        0x3D: 0x40,      // right Option
        0x3E: 0x2000,    // right Control
        0x3F: 0x800000,  // Fn (secondary Fn)
    ]

    static func scancode(forKeyCode keyCode: UInt16) -> Int? {
        base[keyCode]
    }

    /// uiohook scancodes ordered most specific first; empty for unknown keys (silent).
    static func candidates(forKeyCode keyCode: UInt16) -> [Int] {
        candidateTable[keyCode] ?? []
    }

    /// Caps Lock (0x39) deliberately has no mask; it is special-cased by the engine.
    static func modifierMask(forKeyCode keyCode: UInt16) -> UInt64? {
        modifierMasks[keyCode]
    }
}
