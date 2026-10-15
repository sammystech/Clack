import Foundation

/// SplitMix64. Deterministic across launches and machines, so every built-in pack
/// renders to identical samples from the same inputs.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    mutating func unit() -> Double {
        Double(next() >> 11) / 9_007_199_254_740_992.0   // 2^53
    }

    /// Uniform in [a, b).
    mutating func uniform(_ a: Double, _ b: Double) -> Double {
        a + (b - a) * unit()
    }
}

/// FNV-1a 64-bit over the UTF-8 bytes. Used for seeds instead of `hashValue`,
/// which Swift randomizes per launch.
func fnv1a64(_ s: String) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in s.utf8 {
        hash ^= UInt64(byte)
        hash &*= 0x0000_0100_0000_01b3
    }
    return hash
}
