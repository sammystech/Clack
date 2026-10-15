import Foundation

// Original procedural recipes for the built-in packs. Values are parameters
// (frequencies in Hz, levels in dB relative, decay constants in ms), not samples.

/// Band-passed white-noise burst with a fast attack and exponential decay.
struct NoiseTick: Sendable {
    var offsetMs: Double
    var fc: Double
    var q: Double
    var burstMs: Double
    var tauMs: Double
    var db: Double
}

/// Decaying sine partial. `offsetMs` is added to the event's `modesOffsetMs`.
struct ToneMode: Sendable {
    var freq: Double
    var db: Double
    var tauMs: Double
    var offsetMs: Double = 0
}

/// Low sine thump with a 2 ms pitch drop from 1.3x to `freq`.
struct BodyThump: Sendable {
    var freq: Double
    var db: Double
    var tauMs: Double
    var offsetMs: Double = 0
}

/// Noise band whose band-pass center sweeps linearly over time; amplitude rises
/// linearly over `attackMs`, then falls linearly to 0 at `endMs`.
struct NoiseSweep: Sendable {
    var startMs: Double
    var endMs: Double
    var fcStart: Double
    var fcEnd: Double
    var q: Double
    var attackMs: Double
    var db: Double
}

struct EventRecipe: Sendable {
    var ticks: [NoiseTick]
    var modes: [ToneMode]
    var modesOffsetMs: Double = 0
    var body: BodyThump? = nil
    var lowpassHz: Double? = nil
    var gainDb: Double = 0
    var lengthMs: Double
    var sweep: NoiseSweep? = nil
}

struct SwitchRecipe: Sendable {
    var press: EventRecipe
    var release: EventRecipe
    /// Used for the `.enter` press only, without per-group scaling.
    var enterPressOverride: EventRecipe? = nil
}

enum SwitchRecipes {
    static func recipe(for packID: String) -> SwitchRecipe? {
        switch packID {
        case "builtin.linear": linear
        case "builtin.tactile": tactile
        case "builtin.clicky": clicky
        case "builtin.thock": thock
        case "builtin.typewriter": typewriter
        default: nil
        }
    }

    // Smooth, mid-low, soft.
    static let linear = SwitchRecipe(
        press: EventRecipe(
            ticks: [tick(0, 1200, 1.2, 1.0, 7.8, -6)],
            modes: [mode(759, 0, 25), mode(1351, 0, 22), mode(1007, -1, 25), mode(2837, -4, 10), mode(1615, -5, 18)],
            lowpassHz: 6000,
            lengthMs: 240),
        release: EventRecipe(
            ticks: [tick(0, 900, 1.2, 0.8, 6, -8)],
            modes: [mode(759, 0, 20), mode(1351, -2, 16), mode(581, -4, 22)],
            gainDb: -13,
            lengthMs: 200))

    // Dry, bright mid: tactile bump then bottom-out.
    static let tactile = SwitchRecipe(
        press: EventRecipe(
            ticks: [tick(0, 1800, 1.5, 0.6, 2, -10), tick(7, 2600, 2.0, 0.8, 2.6, 0)],
            modes: [mode(2320, 0, 6), mode(2880, -1.6, 6), mode(3413, -2.6, 5), mode(1174, -6, 12), mode(3957, -7, 4)],
            modesOffsetMs: 7,
            lengthMs: 220),
        release: EventRecipe(
            ticks: [tick(0, 2300, 2.0, 0.6, 2.5, -4)],
            modes: [mode(2293, 0, 6), mode(1034, -2, 12), mode(581, -5, 15)],
            gainDb: -12,
            lengthMs: 180))

    // Crisp click jacket, then bottom-out at 20 ms.
    static let clicky = SwitchRecipe(
        press: EventRecipe(
            ticks: [tick(0, 9500, 2.0, 0.6, 2.2, 0), tick(20, 3000, 1.5, 0.8, 3, -3)],
            modes: [
                mode(9168, 0, 6), mode(8118, -4, 6), mode(12565, -7, 4), mode(7203, -9, 5), mode(9400, -6, 8),
                mode(3025, -3, 8, at: 20), mode(1389, -7, 12, at: 20), mode(1007, -9, 15, at: 20),
            ],
            lengthMs: 260),
        release: EventRecipe(
            ticks: [tick(0, 6000, 2.0, 0.5, 2, -2)],
            modes: [mode(1389, 0, 10), mode(1007, -2, 14), mode(2912, -4, 8)],
            gainDb: -14,
            lengthMs: 200))

    // Deep, rounded, dome-like. Release is as loud and brighter.
    static let thock = SwitchRecipe(
        press: EventRecipe(
            ticks: [tick(0, 1000, 1.0, 1.2, 9, -10)],
            modes: [mode(571, -3, 30), mode(705, -4, 28), mode(856, -6.5, 26), mode(990, -8, 24), mode(1378, -12, 15)],
            body: BodyThump(freq: 160, db: 0, tauMs: 22),
            lowpassHz: 2800,
            lengthMs: 280),
        release: EventRecipe(
            ticks: [tick(0, 1600, 1.5, 0.8, 5, -6)],
            modes: [mode(1540, 0, 18), mode(1174, -2, 22), mode(1787, -4, 14)],
            lowpassHz: 4000,
            lengthMs: 220))

    // Metallic strike plus platen thud; Enter is a carriage return.
    static let typewriter = SwitchRecipe(
        press: EventRecipe(
            ticks: [tick(0, 4500, 1.0, 1.5, 4, 0), tick(6, 2500, 1.2, 1.0, 4, -8)],
            modes: [mode(2210, 0, 45), mode(3720, -3, 35), mode(5150, -6, 25), mode(1480, -8, 40)],
            body: BodyThump(freq: 180, db: -4, tauMs: 18),
            lengthMs: 320),
        release: EventRecipe(
            ticks: [tick(0, 3000, 1.2, 0.8, 4, 0)],
            modes: [mode(1800, 0, 20), mode(2600, -4, 15)],
            gainDb: -10,
            lengthMs: 220),
        enterPressOverride: EventRecipe(
            ticks: [],
            modes: [mode(2093, -14, 180, at: 150)],
            body: BodyThump(freq: 120, db: -4, tauMs: 20, offsetMs: 300),
            lengthMs: 700,
            sweep: NoiseSweep(startMs: 0, endMs: 140, fcStart: 1500, fcEnd: 3500, q: 1.5, attackMs: 20, db: -12)))

    private static func tick(_ offset: Double, _ fc: Double, _ q: Double, _ burst: Double, _ tau: Double, _ db: Double) -> NoiseTick {
        NoiseTick(offsetMs: offset, fc: fc, q: q, burstMs: burst, tauMs: tau, db: db)
    }

    private static func mode(_ freq: Double, _ db: Double, _ tau: Double, at offset: Double = 0) -> ToneMode {
        ToneMode(freq: freq, db: db, tauMs: tau, offsetMs: offset)
    }
}
