import AVFoundation
import os

/// A loaded Mechvibes pack. Tables are immutable after init; only the
/// "last variant played" memory is mutable, guarded by an unfair lock.
nonisolated final class MechvibesBank: SoundBank, @unchecked Sendable {
    let packID: String
    let hasKeyUpSounds: Bool

    private let down: [Int: [AVAudioPCMBuffer]]
    private let up: [Int: [AVAudioPCMBuffer]]
    private let fallbackDown: [AVAudioPCMBuffer]
    private let fallbackUp: [AVAudioPCMBuffer]

    /// Last picked index per (key, phase), so a key never repeats the same variant twice in a row.
    private let lastIndex = OSAllocatedUnfairLock(initialState: [Int: Int]())

    private static let fallbackKey = Int.min / 4

    init(packID: String,
         down: [Int: [AVAudioPCMBuffer]],
         up: [Int: [AVAudioPCMBuffer]],
         fallbackDown: [AVAudioPCMBuffer],
         fallbackUp: [AVAudioPCMBuffer]) {
        self.packID = packID
        self.down = down
        self.up = up
        self.fallbackDown = fallbackDown
        self.fallbackUp = fallbackUp
        self.hasKeyUpSounds = !up.isEmpty || !fallbackUp.isEmpty
    }

    var downKeyCount: Int { down.count }
    var upKeyCount: Int { up.count }

    func buffer(for candidates: [Int], phase: KeyPhase) -> AVAudioPCMBuffer? {
        let table = phase == .down ? down : up
        for code in candidates {
            if let variants = table[code], !variants.isEmpty {
                return pick(variants, key: code, phase: phase)
            }
        }
        let fallback = phase == .down ? fallbackDown : fallbackUp
        if !fallback.isEmpty {
            return pick(fallback, key: Self.fallbackKey, phase: phase)
        }
        return nil
    }

    private func pick(_ variants: [AVAudioPCMBuffer], key: Int, phase: KeyPhase) -> AVAudioPCMBuffer {
        let count = variants.count
        if count == 1 { return variants[0] }
        let slot = key &* 2 &+ (phase == .up ? 1 : 0)
        let index = lastIndex.withLock { last -> Int in
            var i: Int
            if let previous = last[slot], previous < count {
                i = Int.random(in: 0..<(count - 1))
                if i >= previous { i += 1 }
            } else {
                i = Int.random(in: 0..<count)
            }
            last[slot] = i
            return i
        }
        return variants[index]
    }
}
