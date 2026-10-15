import AVFoundation
import Foundation

/// The five original procedural packs that ship with Clack.
enum BuiltInPacks {
    struct Info: Sendable, Hashable {
        let id: String
        let name: String
    }

    enum BuiltInPackError: LocalizedError {
        case unknownPack
        var errorDescription: String? { "Unknown built-in pack." }
    }

    static let catalog: [Info] = [
        Info(id: "builtin.linear", name: "Linear"),
        Info(id: "builtin.tactile", name: "Tactile"),
        Info(id: "builtin.clicky", name: "Clicky"),
        Info(id: "builtin.thock", name: "Thock"),
        Info(id: "builtin.typewriter", name: "Typewriter"),
    ]

    static let defaultPackID = "builtin.linear"

    static let variantsPerSlot = 8

    static func makeBank(id: String) async throws -> any SoundBank {
        try await cache.bank(for: id, priority: .userInitiated)
    }

    /// Renders every pack not yet cached, one at a time, at utility priority.
    static func preloadAll() async {
        for info in catalog {
            _ = try? await cache.bank(for: info.id, priority: .utility)
        }
    }

    private static let cache = BankCache()

    /// Caches rendered banks; concurrent requests for one id share a single render.
    private actor BankCache {
        private var banks: [String: any SoundBank] = [:]
        private var inFlight: [String: Task<any SoundBank, Never>] = [:]

        func bank(for id: String, priority: TaskPriority) async throws -> any SoundBank {
            if let bank = banks[id] { return bank }
            if let task = inFlight[id] { return await task.value }
            guard let recipe = SwitchRecipes.recipe(for: id) else { throw BuiltInPackError.unknownPack }
            let task = Task.detached(priority: priority) { () -> any SoundBank in
                BuiltInPacks.render(packID: id, recipe: recipe)
            }
            inFlight[id] = task
            let bank = await task.value
            banks[id] = bank
            inFlight[id] = nil
            return bank
        }
    }

    // MARK: - Rendering (never on the main actor)

    private static func render(packID: String, recipe: SwitchRecipe) -> SynthBank {
        // Render every (group, phase, variant) to mono samples.
        var mono: [KeyGroup: [KeyPhase: [[Float]]]] = [:]
        for group in KeyGroup.allCases {
            for phase in [KeyPhase.down, .up] {
                mono[group, default: [:]][phase] = (0..<variantsPerSlot).map { variant in
                    SwitchSynth.render(recipe: recipe, group: group, phase: phase, variant: variant, packID: packID)
                }
            }
        }

        // One scale for the whole pack: letter press, variant 0 peaks at -6 dBFS.
        let reference = mono[.letter]?[.down]?.first ?? []
        let peak = reference.reduce(Float(0)) { max($0, abs($1)) }
        let scale: Float = peak > 0 ? 0.501 / peak : 1

        var buffers: [KeyGroup: [KeyPhase: [AVAudioPCMBuffer]]] = [:]
        for (group, phases) in mono {
            for (phase, variants) in phases {
                buffers[group, default: [:]][phase] = variants.compactMap { makeBuffer($0, scale: scale) }
            }
        }
        return SynthBank(packID: packID, buffers: buffers)
    }

    /// Scales, soft-limits above 0.95 and copies the same samples to both channels.
    private static func makeBuffer(_ samples: [Float], scale: Float) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: AudioFormat.canonical, frameCapacity: frames),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = frames
        let left = channels[0]
        let right = channels[1]
        for i in 0..<samples.count {
            var x = samples[i] * scale
            let a = abs(x)
            if a > 0.95 {
                x = (x < 0 ? -1 : 1) * (0.95 + 0.05 * tanh((a - 0.95) / 0.05))
            }
            left[i] = x
            right[i] = x
        }
        return buffer
    }
}
