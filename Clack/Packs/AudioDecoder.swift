import AVFoundation
import os

/// Decodes any audio file into a buffer in `AudioFormat.canonical`
/// (48 kHz, 2 channels, Float32, non-interleaved). Runs off the main actor.
nonisolated enum AudioDecoder {
    private static let targetRate: Double = 48_000
    /// Longest accepted file: 10 minutes at 48 kHz.
    private static let maxFrames: AVAudioFramePosition = 48_000 * 600
    private static let ffmpegTimeout: TimeInterval = 20
    private static let ffmpegCandidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]

    static func decode(url: URL) async throws -> AVAudioPCMBuffer {
        try Task.checkCancellation()
        let raw: AVAudioPCMBuffer
        do {
            raw = try readFile(url)
        } catch let error as PackError {
            throw error
        } catch {
            // Path B: typically .ogg, which Core Audio may not read.
            raw = try await decodeWithFFmpeg(url)
        }
        try Task.checkCancellation()
        return try toCanonical(raw)
    }

    // MARK: Path A

    private static func readFile(_ url: URL) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: url)
        let length = file.length
        guard length <= maxFrames else { throw PackError.tooLarge }
        guard length > 0 else { throw PackError.decodeFailed("\(url.lastPathComponent) is empty.") }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(length)) else {
            throw PackError.decodeFailed("out of memory")
        }
        try file.read(into: buffer)
        return buffer
    }

    // MARK: Path B (ffmpeg fallback)

    private static func decodeWithFFmpeg(_ url: URL) async throws -> AVAudioPCMBuffer {
        let fm = FileManager.default
        guard let ffmpeg = ffmpegCandidates.first(where: { fm.isExecutableFile(atPath: $0) }) else {
            let ext = url.pathExtension.isEmpty ? "audio" : url.pathExtension.lowercased()
            throw PackError.unsupportedAudio(ext)
        }

        let cacheDir = PackPaths.decodedCache
        try? fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let key = PackPaths.cacheKey(for: url, prefix: 24)
        let dst = cacheDir.appendingPathComponent("\(key).wav")

        if !fm.fileExists(atPath: dst.path) {
            // Write to a temp name first so a killed ffmpeg never leaves a broken cache entry.
            let tmp = cacheDir.appendingPathComponent("\(key).\(UUID().uuidString).tmp.wav")
            defer { try? fm.removeItem(at: tmp) }
            let result = try await ProcessRunner.run(ffmpeg, [
                "-v", "error", "-nostdin", "-y", "-i", url.path,
                "-ac", "2", "-ar", "48000", "-c:a", "pcm_f32le", tmp.path,
            ], timeout: ffmpegTimeout)
            try Task.checkCancellation()
            if result.timedOut { throw PackError.decodeFailed("ffmpeg timed out") }
            guard result.status == 0, fm.fileExists(atPath: tmp.path) else {
                let detail = result.errorOutput.split(separator: "\n").last.map(String.init)
                throw PackError.decodeFailed(detail ?? "ffmpeg couldn't convert \(url.lastPathComponent)")
            }
            if !fm.fileExists(atPath: dst.path) {
                try? fm.moveItem(at: tmp, to: dst)
            }
        }

        do {
            return try readFile(dst)
        } catch let error as PackError {
            throw error
        } catch {
            try? fm.removeItem(at: dst)
            throw PackError.decodeFailed(error.localizedDescription)
        }
    }

    // MARK: Conversion

    private final class FeedState: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer
        var fed = false
        init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    }

    private static func toCanonical(_ src: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        let canonical = AudioFormat.canonical
        let srcFormat = src.format
        if srcFormat === canonical { return src }

        let isCanonicalLayout = srcFormat.commonFormat == .pcmFormatFloat32
            && srcFormat.sampleRate == targetRate
            && !srcFormat.isInterleaved
        if isCanonicalLayout && (srcFormat.channelCount == 1 || srcFormat.channelCount == 2) {
            return try copyToCanonical(src)
        }

        let channels = min(srcFormat.channelCount, 2)
        guard channels > 0,
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: targetRate,
                                         channels: channels, interleaved: false),
              let converter = AVAudioConverter(from: srcFormat, to: target) else {
            throw PackError.decodeFailed("unsupported audio format")
        }
        if srcFormat.channelCount > 2 { converter.downmix = true }

        let capacity = AVAudioFrameCount(
            (Double(src.frameLength) * targetRate / srcFormat.sampleRate).rounded(.up)) + 4096
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            throw PackError.decodeFailed("out of memory")
        }

        let state = FeedState(src)
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if state.fed {
                inputStatus.pointee = .endOfStream
                return nil
            }
            state.fed = true
            inputStatus.pointee = .haveData
            return state.buffer
        }
        if status == .error {
            throw PackError.decodeFailed(error?.localizedDescription ?? "conversion failed")
        }
        return try copyToCanonical(out)
    }

    /// Copies a 48 kHz Float32 non-interleaved mono or stereo buffer into a buffer whose
    /// format object is exactly `AudioFormat.canonical`. Mono is duplicated to both channels.
    private static func copyToCanonical(_ src: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        let frames = src.frameLength
        guard frames > 0 else { throw PackError.decodeFailed("the file has no audio") }
        guard let dst = AVAudioPCMBuffer(pcmFormat: AudioFormat.canonical, frameCapacity: frames),
              let srcData = src.floatChannelData, let dstData = dst.floatChannelData else {
            throw PackError.decodeFailed("out of memory")
        }
        dst.frameLength = frames
        let bytes = Int(frames) * MemoryLayout<Float>.size
        let srcChannels = Int(src.format.channelCount)
        for ch in 0..<2 {
            memcpy(dstData[ch], srcData[min(ch, srcChannels - 1)], bytes)
        }
        return dst
    }
}
