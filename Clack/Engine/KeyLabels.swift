import Foundation

/// Short on-screen labels for macOS virtual key codes (US layout positions).
enum KeyLabels {
    static func label(forKeyCode code: UInt16) -> String? { table[code] }
    static var allLabels: [String] { Array(table.values) }

    private static let table: [UInt16: String] = {
        var t: [UInt16: String] = [:]
        let letters: [(UInt16, String)] = [
            (0x00, "A"), (0x0B, "B"), (0x08, "C"), (0x02, "D"), (0x0E, "E"), (0x03, "F"), (0x05, "G"),
            (0x04, "H"), (0x22, "I"), (0x26, "J"), (0x28, "K"), (0x25, "L"), (0x2E, "M"), (0x2D, "N"),
            (0x1F, "O"), (0x23, "P"), (0x0C, "Q"), (0x0F, "R"), (0x01, "S"), (0x11, "T"), (0x20, "U"),
            (0x09, "V"), (0x0D, "W"), (0x07, "X"), (0x10, "Y"), (0x06, "Z"),
            (0x12, "1"), (0x13, "2"), (0x14, "3"), (0x15, "4"), (0x17, "5"), (0x16, "6"), (0x1A, "7"),
            (0x1C, "8"), (0x19, "9"), (0x1D, "0"),
            (0x1B, "-"), (0x18, "="), (0x21, "["), (0x1E, "]"), (0x2A, "\\"), (0x29, ";"), (0x27, "'"),
            (0x2B, ","), (0x2F, "."), (0x2C, "/"), (0x32, "`"),
            (0x31, "Space"), (0x24, "Return"), (0x4C, "Enter"), (0x30, "Tab"), (0x33, "Delete"),
            (0x75, "Del"), (0x35, "Esc"), (0x39, "Caps Lock"),
            (0x38, "⇧"), (0x3C, "⇧"), (0x3B, "⌃"), (0x3E, "⌃"), (0x3A, "⌥"), (0x3D, "⌥"),
            (0x37, "⌘"), (0x36, "⌘"), (0x3F, "fn"),
            (0x7B, "←"), (0x7C, "→"), (0x7D, "↓"), (0x7E, "↑"),
            (0x73, "Home"), (0x77, "End"), (0x74, "Page Up"), (0x79, "Page Down"),
            (0x7A, "F1"), (0x78, "F2"), (0x63, "F3"), (0x76, "F4"), (0x60, "F5"), (0x61, "F6"),
            (0x62, "F7"), (0x64, "F8"), (0x65, "F9"), (0x6D, "F10"), (0x67, "F11"), (0x6F, "F12"),
            (0x69, "F13"), (0x6B, "F14"), (0x71, "F15"),
            (0xA0, "Mission Control"), (0x83, "Launchpad"), (0xB1, "Spotlight"), (0xB0, "Dictation"),
            (0xB2, "Focus"),
            (0x52, "0"), (0x53, "1"), (0x54, "2"), (0x55, "3"), (0x56, "4"), (0x57, "5"), (0x58, "6"),
            (0x59, "7"), (0x5B, "8"), (0x5C, "9"), (0x41, "."), (0x43, "*"), (0x45, "+"), (0x4B, "/"),
            (0x4E, "-"), (0x51, "="), (0x47, "Clear"),
        ]
        for (code, label) in letters { t[code] = label }
        return t
    }()
}
