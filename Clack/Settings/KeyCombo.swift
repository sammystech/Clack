import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut in Carbon terms (virtual key code + Carbon modifier mask).
struct KeyCombo: Codable, Equatable, Hashable, Sendable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    // Carbon modifier masks.
    static let cmdMask: UInt32 = 0x0100
    static let shiftMask: UInt32 = 0x0200
    static let optionMask: UInt32 = 0x0800
    static let controlMask: UInt32 = 0x1000

    /// Control+Option+Command+M.
    static let defaultMute = KeyCombo(keyCode: 46, carbonModifiers: 0x1000 | 0x0800 | 0x0100)

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    /// Builds a combo from a keyDown event. Returns nil unless Command, Control or Option is held
    /// (Shift alone is not enough) and the key itself is not a bare modifier.
    init?(event: NSEvent) {
        guard event.type == .keyDown else { return nil }
        let code = UInt32(event.keyCode)
        guard !Self.modifierKeyCodes.contains(code) else { return nil }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.isDisjoint(with: [.command, .control, .option]) else { return nil }
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= Self.cmdMask }
        if flags.contains(.shift) { mods |= Self.shiftMask }
        if flags.contains(.option) { mods |= Self.optionMask }
        if flags.contains(.control) { mods |= Self.controlMask }
        self.init(keyCode: code, carbonModifiers: mods)
    }

    /// For example "⌃⌥⌘M".
    var displayString: String {
        var s = ""
        if carbonModifiers & Self.controlMask != 0 { s += "⌃" }
        if carbonModifiers & Self.optionMask != 0 { s += "⌥" }
        if carbonModifiers & Self.shiftMask != 0 { s += "⇧" }
        if carbonModifiers & Self.cmdMask != 0 { s += "⌘" }
        return s + keyName
    }

    /// Key equivalent for NSMenuItem, only for single-character keys.
    var menuKeyEquivalent: (String, NSEvent.ModifierFlags)? {
        guard let character = Self.characterKeys[keyCode] else { return nil }
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & Self.cmdMask != 0 { flags.insert(.command) }
        if carbonModifiers & Self.shiftMask != 0 { flags.insert(.shift) }
        if carbonModifiers & Self.optionMask != 0 { flags.insert(.option) }
        if carbonModifiers & Self.controlMask != 0 { flags.insert(.control) }
        return (character.lowercased(), flags)
    }

    // MARK: - Key names

    private var keyName: String {
        if let character = Self.characterKeys[keyCode] { return character }
        if let name = Self.namedKeys[keyCode] { return name }
        return "Key \(keyCode)"
    }

    private static let modifierKeyCodes: Set<UInt32> = [
        UInt32(kVK_Command), UInt32(kVK_RightCommand), UInt32(kVK_Shift), UInt32(kVK_RightShift),
        UInt32(kVK_Option), UInt32(kVK_RightOption), UInt32(kVK_Control), UInt32(kVK_RightControl),
        UInt32(kVK_CapsLock), UInt32(kVK_Function),
    ]

    /// ANSI letters, digits and punctuation.
    private static let characterKeys: [UInt32: String] = {
        let pairs: [(Int, String)] = [
            (kVK_ANSI_A, "A"), (kVK_ANSI_B, "B"), (kVK_ANSI_C, "C"), (kVK_ANSI_D, "D"),
            (kVK_ANSI_E, "E"), (kVK_ANSI_F, "F"), (kVK_ANSI_G, "G"), (kVK_ANSI_H, "H"),
            (kVK_ANSI_I, "I"), (kVK_ANSI_J, "J"), (kVK_ANSI_K, "K"), (kVK_ANSI_L, "L"),
            (kVK_ANSI_M, "M"), (kVK_ANSI_N, "N"), (kVK_ANSI_O, "O"), (kVK_ANSI_P, "P"),
            (kVK_ANSI_Q, "Q"), (kVK_ANSI_R, "R"), (kVK_ANSI_S, "S"), (kVK_ANSI_T, "T"),
            (kVK_ANSI_U, "U"), (kVK_ANSI_V, "V"), (kVK_ANSI_W, "W"), (kVK_ANSI_X, "X"),
            (kVK_ANSI_Y, "Y"), (kVK_ANSI_Z, "Z"),
            (kVK_ANSI_0, "0"), (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"),
            (kVK_ANSI_4, "4"), (kVK_ANSI_5, "5"), (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"),
            (kVK_ANSI_8, "8"), (kVK_ANSI_9, "9"),
            (kVK_ANSI_Minus, "-"), (kVK_ANSI_Equal, "="), (kVK_ANSI_LeftBracket, "["),
            (kVK_ANSI_RightBracket, "]"), (kVK_ANSI_Semicolon, ";"), (kVK_ANSI_Quote, "'"),
            (kVK_ANSI_Comma, ","), (kVK_ANSI_Period, "."), (kVK_ANSI_Slash, "/"),
            (kVK_ANSI_Backslash, "\\"), (kVK_ANSI_Grave, "`"),
        ]
        return Dictionary(uniqueKeysWithValues: pairs.map { (UInt32($0.0), $0.1) })
    }()

    private static let namedKeys: [UInt32: String] = {
        let pairs: [(Int, String)] = [
            (kVK_F1, "F1"), (kVK_F2, "F2"), (kVK_F3, "F3"), (kVK_F4, "F4"), (kVK_F5, "F5"),
            (kVK_F6, "F6"), (kVK_F7, "F7"), (kVK_F8, "F8"), (kVK_F9, "F9"), (kVK_F10, "F10"),
            (kVK_F11, "F11"), (kVK_F12, "F12"), (kVK_F13, "F13"), (kVK_F14, "F14"),
            (kVK_F15, "F15"), (kVK_F16, "F16"), (kVK_F17, "F17"), (kVK_F18, "F18"),
            (kVK_F19, "F19"), (kVK_F20, "F20"),
            (kVK_Space, "Space"), (kVK_Return, "Return"), (kVK_Tab, "Tab"),
            (kVK_Delete, "Delete"), (kVK_ForwardDelete, "Forward Delete"), (kVK_Escape, "Escape"),
            (kVK_LeftArrow, "←"), (kVK_RightArrow, "→"), (kVK_DownArrow, "↓"), (kVK_UpArrow, "↑"),
            (kVK_Home, "Home"), (kVK_End, "End"), (kVK_PageUp, "Page Up"), (kVK_PageDown, "Page Down"),
        ]
        return Dictionary(uniqueKeysWithValues: pairs.map { (UInt32($0.0), $0.1) })
    }()
}
