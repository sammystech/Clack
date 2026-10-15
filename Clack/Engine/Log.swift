import os

/// Unified logging. Never log key codes, characters, per-key counts or anything typed.
enum Log {
    private static let subsystem = "com.samuelmittman.Clack"
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let packs = Logger(subsystem: subsystem, category: "packs")
    static let input = Logger(subsystem: subsystem, category: "input")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
