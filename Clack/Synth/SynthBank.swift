import AVFoundation
import os

/// Immutable set of procedurally rendered built-in sounds: 8 variants per
/// (key group, phase). Safe to call from the key-tap thread.
final class SynthBank: SoundBank, @unchecked Sendable {
    let packID: String
    let hasKeyUpSounds = true

    /// Flattened: slot = group index * 2 + phase index.
    private let slots: [[AVAudioPCMBuffer]]
    private let lastIndex: OSAllocatedUnfairLock<[Int: Int]>

    init(packID: String, buffers: [KeyGroup: [KeyPhase: [AVAudioPCMBuffer]]]) {
        self.packID = packID
        var slots: [[AVAudioPCMBuffer]] = []
        var last: [Int: Int] = [:]
        for group in KeyGroup.allCases {
            for phase in [KeyPhase.down, .up] {
                last[slots.count] = -1
                slots.append(buffers[group]?[phase] ?? [])
            }
        }
        self.slots = slots
        self.lastIndex = OSAllocatedUnfairLock(initialState: last)
    }

    func buffer(for candidates: [Int], phase: KeyPhase) -> AVAudioPCMBuffer? {
        guard let first = candidates.first else { return nil }
        let slot = Self.groupIndex(KeyGroup(scancode: first)) * 2 + (phase == .down ? 0 : 1)
        let variants = slots[slot]
        let count = variants.count
        guard count > 0 else { return nil }
        let index = lastIndex.withLock { last -> Int in
            let previous = last[slot] ?? -1
            var pick: Int
            if count == 1 || previous < 0 || previous >= count {
                pick = Int.random(in: 0..<count)
            } else {
                pick = Int.random(in: 0..<(count - 1))   // never the same variant twice in a row
                if pick >= previous { pick += 1 }
            }
            last[slot] = pick
            return pick
        }
        return variants[index]
    }

    private static func groupIndex(_ group: KeyGroup) -> Int {
        switch group {
        case .letter: 0
        case .modifier: 1
        case .wide: 2
        case .backspace: 3
        case .enter: 4
        case .space: 5
        }
    }
}
