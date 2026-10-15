import AVFoundation

/// "Speak keys" joke mode: says each key out loud. Every label is pre-rendered once with
/// AVSpeechSynthesizer (fast rate, silence trimmed) and played from a pool of player nodes,
/// so presses play instantly and overlap when typing fast.
@MainActor final class KeySpeaker {
    static let shared = KeySpeaker()

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var format: AVAudioFormat?
    private var clips: [String: AVAudioPCMBuffer] = [:]
    var readyCount: Int { clips.count }
    func clipSeconds(_ label: String) -> Double? { clips[label].map { Double($0.frameLength) / $0.format.sampleRate } }
    private var isPreparing = false
    private let synthesizer = AVSpeechSynthesizer()
    private static let voiceCount = 10

    /// Renders every label in the background. Safe to call repeatedly.
    func prepare() {
        guard !isPreparing, clips.isEmpty else { return }
        isPreparing = true
        let labels = Array(Set(KeyLabels.allLabels))
        Task { @MainActor in
            for label in labels {
                if let buffer = await render(Self.spokenText(for: label)) {
                    clips[label] = buffer
                }
            }
            isPreparing = false
        }
    }

    func speak(_ label: String, volume: Float) {
        guard let clip = clips[label] else { prepare(); return }
        if players.isEmpty || format != clip.format { setUpEngine(format: clip.format) }
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning, !players.isEmpty else { return }
        engine.mainMixerNode.outputVolume = volume
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.stop()
        player.scheduleBuffer(clip, at: nil, options: [])
        player.play()
    }

    // MARK: - Private

    private func setUpEngine(format: AVAudioFormat) {
        engine.stop()
        for player in players { engine.detach(player) }
        players = (0..<Self.voiceCount).map { _ in
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            return player
        }
        self.format = format
    }

    /// One utterance -> one trimmed buffer.
    private func render(_ text: String) async -> AVAudioPCMBuffer? {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceMaximumSpeechRate * 0.62
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        return await withCheckedContinuation { continuation in
            nonisolated(unsafe) var chunks: [AVAudioPCMBuffer] = []
            nonisolated(unsafe) var finished = false
            synthesizer.write(utterance) { buffer in
                guard !finished, let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 {
                    finished = true
                    nonisolated(unsafe) let joined = Self.joinAndTrim(chunks)
                    continuation.resume(returning: joined)
                } else {
                    chunks.append(pcm)
                }
            }
        }
    }

    nonisolated private static func joinAndTrim(_ chunks: [AVAudioPCMBuffer]) -> AVAudioPCMBuffer? {
        guard let first = chunks.first else { return nil }
        let fmt = first.format
        let total = chunks.reduce(0) { $0 + Int($1.frameLength) }
        // Work in Float32 mono-or-matching layout.
        guard let floatFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: fmt.sampleRate,
                                              channels: fmt.channelCount, interleaved: false),
              let joined = AVAudioPCMBuffer(pcmFormat: floatFormat, frameCapacity: AVAudioFrameCount(total)),
              let dst = joined.floatChannelData else { return nil }
        var offset = 0
        for chunk in chunks {
            let n = Int(chunk.frameLength)
            for ch in 0..<Int(fmt.channelCount) {
                if let src = chunk.floatChannelData?[ch] {
                    (dst[ch] + offset).update(from: src, count: n)
                } else if let src = chunk.int16ChannelData?[ch] {
                    for i in 0..<n { dst[ch][offset + i] = Float(src[i]) / 32768 }
                }
            }
            offset += n
        }
        // Trim leading/trailing near-silence so presses feel instant.
        let threshold: Float = 0.01
        let samples = dst[0]
        var start = 0, end = total
        while start < end, abs(samples[start]) < threshold { start += 1 }
        while end > start, abs(samples[end - 1]) < threshold { end -= 1 }
        let count = end - start
        guard count > 0, let out = AVAudioPCMBuffer(pcmFormat: floatFormat, frameCapacity: AVAudioFrameCount(count)),
              let outData = out.floatChannelData else { return nil }
        out.frameLength = AVAudioFrameCount(count)
        for ch in 0..<Int(fmt.channelCount) {
            outData[ch].update(from: dst[ch] + start, count: count)
        }
        return out
    }

    private static func spokenText(for label: String) -> String {
        switch label {
        case "⌘": return "command"
        case "⇧": return "shift"
        case "⌥": return "option"
        case "⌃": return "control"
        case "←": return "left"
        case "→": return "right"
        case "↑": return "up"
        case "↓": return "down"
        case "-": return "dash"
        case "=": return "equals"
        case "[": return "bracket"
        case "]": return "bracket"
        case "\\": return "backslash"
        case ";": return "semicolon"
        case "'": return "quote"
        case ",": return "comma"
        case ".": return "dot"
        case "/": return "slash"
        case "`": return "tick"
        case "*": return "star"
        case "+": return "plus"
        case "Esc": return "escape"
        case "Del": return "delete"
        case "fn": return "function"
        default: return label.count == 1 ? label.lowercased() : label
        }
    }
}
