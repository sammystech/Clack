import AVFoundation
import os

/// Turns a custom pack descriptor into a playable `MechvibesBank`.
nonisolated enum MechvibesPackLoader {
    static let timeout: Duration = .seconds(15)
    static let maxConcurrentDecodes = 4
    static let maxDecodedBytes = 200 * 1024 * 1024
    /// 4 ms linear fade at 48 kHz, applied to the end of every sliced sprite.
    static let spriteFadeFrames = 192
    private static let framesPerMs = 48.0

    static func load(_ d: PackDescriptor) async throws -> MechvibesBank {
        try await withThrowingTaskGroup(of: MechvibesBank.self) { group in
            group.addTask { try await loadUnbounded(d) }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw PackError.timedOut
            }
            defer { group.cancelAll() }
            guard let bank = try await group.next() else { throw PackError.timedOut }
            return bank
        }
    }

    // MARK: - Loading

    private struct Decoded: @unchecked Sendable {
        let url: URL
        let buffer: AVAudioPCMBuffer?
        let error: (any Error)?
    }

    private static func loadUnbounded(_ d: PackDescriptor) async throws -> MechvibesBank {
        guard let configURL = d.configURL else { throw PackError.noConfig }
        let folder = d.folderURL ?? configURL.deletingLastPathComponent()
        let config = try MechvibesConfig.load(configURL: configURL)

        switch config.defineType {
        case .single: return try await loadSingle(d, config: config, folder: folder)
        case .multi: return try await loadMulti(d, config: config, folder: folder)
        }
    }

    private static func loadSingle(_ d: PackDescriptor, config: MechvibesConfig, folder: URL) async throws -> MechvibesBank {
        guard let soundName = config.sound,
              let soundURL = PackFileResolver.resolve(soundName, in: folder).first else {
            throw PackError.missingSoundFile(config.sound ?? "sound")
        }
        let soundUpURL = config.soundUp.flatMap { PackFileResolver.resolve($0, in: folder).first }

        var files = [soundURL]
        if let soundUpURL, soundUpURL != soundURL { files.append(soundUpURL) }
        let decoded = try await decodeAll(files)

        guard let source = decoded[soundURL]?.buffer else {
            throw decoded[soundURL]?.error ?? PackError.missingSoundFile(soundName)
        }

        var shared: [SpriteKey: AVAudioPCMBuffer] = [:]
        func table(_ defines: [Int: MechvibesConfig.Define]) -> [Int: [AVAudioPCMBuffer]] {
            var out: [Int: [AVAudioPCMBuffer]] = [:]
            for (code, define) in defines {
                guard case .sprite(let startMs, let durationMs) = define else { continue }
                let key = SpriteKey(start: Int((startMs * framesPerMs).rounded()),
                                    count: Int((durationMs * framesPerMs).rounded()))
                if let existing = shared[key] {
                    out[code] = [existing]
                } else if let slice = slice(source, start: key.start, count: key.count) {
                    shared[key] = slice
                    out[code] = [slice]
                }
            }
            return out
        }
        let down = table(config.down)
        let up = table(config.up)

        var fallbackUp: [AVAudioPCMBuffer] = []
        if let soundUpURL {
            if let buffer = decoded[soundUpURL]?.buffer {
                fallbackUp = [buffer]
            } else {
                Log.packs.debug("Pack key-up sound could not be decoded; continuing without it")
            }
        }

        if down.isEmpty && up.isEmpty && fallbackUp.isEmpty { throw PackError.noKeysDefined }
        return MechvibesBank(packID: d.id, down: down, up: up, fallbackDown: [], fallbackUp: fallbackUp)
    }

    private static func loadMulti(_ d: PackDescriptor, config: MechvibesConfig, folder: URL) async throws -> MechvibesBank {
        // Resolve every reference once.
        var resolvedCache: [String: [URL]] = [:]
        func resolve(_ name: String) -> [URL] {
            if let hit = resolvedCache[name] { return hit }
            let urls = PackFileResolver.resolve(name, in: folder)
            resolvedCache[name] = urls
            return urls
        }
        func resolvedTable(_ defines: [Int: MechvibesConfig.Define]) -> [Int: [URL]] {
            var out: [Int: [URL]] = [:]
            for (code, define) in defines {
                guard case .file(let name) = define else { continue }
                let urls = resolve(name)
                if !urls.isEmpty { out[code] = urls }
            }
            return out
        }
        let downURLs = resolvedTable(config.down)
        let upURLs = resolvedTable(config.up)
        let fallbackDownURLs = config.sound.map { resolve($0) } ?? []
        let fallbackUpURLs = config.soundUp.map { resolve($0) } ?? []

        var unique: [URL] = []
        var seen = Set<URL>()
        for url in downURLs.values.flatMap({ $0 }) + upURLs.values.flatMap({ $0 }) + fallbackDownURLs + fallbackUpURLs
        where seen.insert(url).inserted {
            unique.append(url)
        }
        guard !unique.isEmpty else { throw PackError.noSoundsFound }

        let decoded = try await decodeAll(unique)
        func buffers(_ urls: [URL]) -> [AVAudioPCMBuffer] { urls.compactMap { decoded[$0]?.buffer } }

        var down: [Int: [AVAudioPCMBuffer]] = [:]
        var up: [Int: [AVAudioPCMBuffer]] = [:]
        var dropped = 0
        for (code, urls) in downURLs {
            let b = buffers(urls)
            if b.isEmpty { dropped += 1 } else { down[code] = b }
        }
        for (code, urls) in upURLs {
            let b = buffers(urls)
            if b.isEmpty { dropped += 1 } else { up[code] = b }
        }
        dropped += (config.down.count - downURLs.count) + (config.up.count - upURLs.count)
        let fallbackDown = buffers(fallbackDownURLs)
        let fallbackUp = buffers(fallbackUpURLs)

        if dropped > 0 {
            Log.packs.debug("Multi pack loaded with \(dropped, privacy: .public) keys missing sound files")
        }
        if down.isEmpty && up.isEmpty && fallbackDown.isEmpty && fallbackUp.isEmpty {
            // Surface a concrete reason (for example .ogg without ffmpeg) when there is one.
            if let firstError = unique.lazy.compactMap({ decoded[$0]?.error }).first {
                throw firstError
            }
            throw PackError.noSoundsFound
        }
        return MechvibesBank(packID: d.id, down: down, up: up, fallbackDown: fallbackDown, fallbackUp: fallbackUp)
    }

    // MARK: - Decoding

    /// Decodes files in parallel (at most 4 at a time). Individual failures are recorded,
    /// not thrown; exceeding the memory budget or cancellation throws.
    private static func decodeAll(_ urls: [URL]) async throws -> [URL: Decoded] {
        var results: [URL: Decoded] = [:]
        var totalBytes = 0
        try await withThrowingTaskGroup(of: Decoded.self) { group in
            var pending = urls.makeIterator()
            func addNext() {
                guard let url = pending.next() else { return }
                group.addTask {
                    do {
                        return Decoded(url: url, buffer: try await AudioDecoder.decode(url: url), error: nil)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        return Decoded(url: url, buffer: nil, error: error)
                    }
                }
            }
            for _ in 0..<maxConcurrentDecodes { addNext() }
            while let item = try await group.next() {
                if let buffer = item.buffer {
                    totalBytes += Int(buffer.frameLength) * Int(buffer.format.channelCount) * MemoryLayout<Float>.size
                    if totalBytes > maxDecodedBytes {
                        group.cancelAll()
                        throw PackError.tooLarge
                    }
                }
                results[item.url] = item
                addNext()
            }
        }
        return results
    }

    // MARK: - Sprites

    private struct SpriteKey: Hashable {
        let start: Int
        let count: Int
    }

    /// Copies a region of a canonical buffer into a new canonical buffer and fades its tail.
    private static func slice(_ source: AVAudioPCMBuffer, start rawStart: Int, count rawCount: Int) -> AVAudioPCMBuffer? {
        let length = Int(source.frameLength)
        let start = max(0, rawStart)
        guard rawCount > 0, start < length else { return nil }
        let count = min(rawCount, length - start)
        guard count > 0,
              let out = AVAudioPCMBuffer(pcmFormat: AudioFormat.canonical, frameCapacity: AVAudioFrameCount(count)),
              let src = source.floatChannelData, let dst = out.floatChannelData else { return nil }
        out.frameLength = AVAudioFrameCount(count)

        let channels = Int(AudioFormat.canonical.channelCount)
        let sourceChannels = Int(source.format.channelCount)
        let fade = min(spriteFadeFrames, count)
        for ch in 0..<channels {
            let from = src[min(ch, sourceChannels - 1)] + start
            memcpy(dst[ch], from, count * MemoryLayout<Float>.size)
            let samples = dst[ch]
            for i in 0..<fade {
                let gain = Float(fade - 1 - i) / Float(fade)
                samples[count - fade + i] *= gain
            }
        }
        return out
    }
}
