import Foundation
import CryptoKit
import os

// MARK: - Public models

enum PackSource: Sendable, Hashable { case builtIn, custom }

struct PackDescriptor: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let source: PackSource
    let folderURL: URL?
    let configURL: URL?
    let hasKeyUpSounds: Bool
}

struct PackFolder: Identifiable, Sendable, Hashable {
    enum Kind: Sendable { case bundled, managed, mechvibes, mechvibesV2, user }

    let id: String
    let url: URL
    let kind: Kind
    let exists: Bool

    var isRemovable: Bool { kind == .user }

    var displayName: String {
        switch kind {
        case .bundled: "Included Packs"
        case .managed: "Clack Packs"
        case .mechvibes: "Mechvibes Custom"
        case .mechvibesV2: "Mechvibes Custom (2.3.6)"
        case .user: url.lastPathComponent
        }
    }
}

struct PackLoadFailure: Identifiable, Sendable, Hashable {
    let id: String
    let folderName: String
    let url: URL
    let reason: String
}

enum PackError: LocalizedError, Sendable {
    case noConfig
    case invalidJSON(String)
    case unsupportedVersion(Int)
    case missingField(String)
    case missingSoundFile(String)
    case noSoundsFound
    case noKeysDefined
    case unsupportedAudio(String)
    case decodeFailed(String)
    case tooLarge
    case timedOut
    case copyFailed(String)
    case notAPack

    var errorDescription: String? {
        switch self {
        case .noConfig: "No config.json found."
        case .invalidJSON: "config.json isn't valid JSON."
        case .unsupportedVersion(let v): "Unsupported config version \(v)."
        case .missingField(let f): "config.json is missing \"\(f)\"."
        case .missingSoundFile(let n): "Missing sound file \(n)."
        case .noSoundsFound: "None of the pack's sound files were found."
        case .noKeysDefined: "The pack doesn't define any keys."
        case .unsupportedAudio(let ext):
            "macOS can't play .\(ext) files. Install ffmpeg with Homebrew, or convert the pack's audio to WAV."
        case .decodeFailed(let s): "Couldn't read the audio: \(s)"
        case .tooLarge: "This pack is too large to load."
        case .timedOut: "Loading took too long."
        case .copyFailed(let s): "Couldn't copy the pack: \(s)"
        case .notAPack: "This folder doesn't contain a config.json sound pack."
        }
    }
}

// MARK: - Shared paths and helpers (packs workstream internal)

nonisolated enum PackPaths {
    /// ~/Library/Application Support/Clack/Packs
    static var managedFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Clack/Packs", isDirectory: true)
    }

    /// Clack.app/Contents/Resources/Packs (classic Mechvibes packs, MIT; read only)
    static var bundledFolder: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Packs", isDirectory: true)
    }

    /// ~/mechvibes_custom (read only, never created)
    static var mechvibesCustom: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("mechvibes_custom", isDirectory: true)
    }

    /// ~/Library/Application Support/Mechvibes/custom (read only, never created)
    static var mechvibesV2Custom: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Mechvibes/custom", isDirectory: true)
    }

    /// ~/Library/Caches/com.samuelmittman.Clack
    static var cacheRoot: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches")
        return base.appendingPathComponent("com.samuelmittman.Clack", isDirectory: true)
    }

    static var decodedCache: URL { cacheRoot.appendingPathComponent("Decoded", isDirectory: true) }
    static var zipCache: URL { cacheRoot.appendingPathComponent("Zips", isDirectory: true) }

    /// Path used for identity and dedupe: standardized, symlinks resolved.
    static func realPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// sha256("path|size|mtime") as lowercase hex, truncated to `prefix` characters.
    static func cacheKey(for url: URL, prefix: Int) -> String {
        let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let digest = SHA256.hash(data: Data("\(url.standardizedFileURL.path)|\(size)|\(mtime)".utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(prefix))
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Visible entries of a directory, skipping hidden files and __MACOSX, sorted by name.
    static func visibleContents(of dir: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        return items
            .filter { !$0.lastPathComponent.hasPrefix(".") && $0.lastPathComponent != "__MACOSX" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Breadth-first search for config.json (case-insensitive). Depth 0 is `dir` itself.
    /// Returns the shallowest match.
    static func findConfig(in dir: URL, maxDepth: Int) -> URL? {
        var level = [dir]
        for _ in 0...maxDepth {
            var next: [URL] = []
            for folder in level {
                let entries = visibleContents(of: folder)
                if let config = entries.first(where: {
                    $0.lastPathComponent.lowercased() == "config.json" && !isDirectory($0)
                }) {
                    return config
                }
                next.append(contentsOf: entries.filter { isDirectory($0) })
            }
            if next.isEmpty { break }
            level = next
        }
        return nil
    }

    /// Extracts a zip with ditto into `dest` atomically (via a sibling temp folder).
    static func unzip(_ zip: URL, to dest: URL) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        let partial = dest.deletingLastPathComponent()
            .appendingPathComponent(".partial-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: partial) }
        let result = try await ProcessRunner.run(
            "/usr/bin/ditto", ["-x", "-k", zip.path, partial.path], timeout: 60)
        guard result.status == 0, !result.timedOut else { throw PackError.notAPack }
        if fm.fileExists(atPath: dest.path) { return }
        try fm.moveItem(at: partial, to: dest)
    }
}

/// Runs a helper tool (ditto, ffmpeg) without blocking a thread, with a timeout.
/// Cancelling the calling task terminates the process.
nonisolated enum ProcessRunner {
    struct Result: Sendable {
        let status: Int32
        let timedOut: Bool
        let errorOutput: String
    }

    private final class Box: @unchecked Sendable {
        let process = Process()
        let errPipe = Pipe()
        let timedOut = OSAllocatedUnfairLock(initialState: false)
    }

    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async throws -> Result {
        let box = Box()
        box.process.executableURL = URL(fileURLWithPath: executable)
        box.process.arguments = arguments
        box.process.standardInput = FileHandle.nullDevice
        box.process.standardOutput = FileHandle.nullDevice
        box.process.standardError = box.errPipe

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Result, Error>) in
                box.process.terminationHandler = { process in
                    let data = box.errPipe.fileHandleForReading.readDataToEndOfFile()
                    let text = String(decoding: data.prefix(2_000), as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    cont.resume(returning: Result(
                        status: process.terminationStatus,
                        timedOut: box.timedOut.withLock { $0 },
                        errorOutput: text))
                }
                do {
                    try box.process.run()
                } catch {
                    box.process.terminationHandler = nil
                    cont.resume(throwing: error)
                    return
                }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                    if box.process.isRunning {
                        box.timedOut.withLock { $0 = true }
                        box.process.terminate()
                    }
                }
            }
        } onCancel: {
            if box.process.isRunning { box.process.terminate() }
        }
    }
}
