import Foundation

/// Copies a pack folder or .zip into Clack's managed packs folder after validating it.
nonisolated enum PackImporter {
    static func importPack(from url: URL, into managed: URL) async throws -> URL {
        let fm = FileManager.default
        let source = url.standardizedFileURL
        let isZip = source.pathExtension.lowercased() == "zip" && !PackPaths.isDirectory(source)

        var tempDir: URL?
        defer { if let tempDir { try? fm.removeItem(at: tempDir) } }

        let configURL: URL?
        if isZip {
            let temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            tempDir = temp
            let extracted = temp.appendingPathComponent("pack", isDirectory: true)
            try await PackPaths.unzip(source, to: extracted)
            configURL = PackPaths.findConfig(in: extracted, maxDepth: 3)
        } else {
            guard PackPaths.isDirectory(source) else { throw PackError.notAPack }
            configURL = PackPaths.findConfig(in: source, maxDepth: 2)
        }
        guard let configURL else { throw PackError.notAPack }

        let packFolder = configURL.deletingLastPathComponent()
        _ = try MechvibesConfig.load(configURL: configURL)
        try Task.checkCancellation()

        let baseName = isZip ? source.deletingPathExtension().lastPathComponent : packFolder.lastPathComponent
        let name = sanitize(baseName)

        do {
            try fm.createDirectory(at: managed, withIntermediateDirectories: true)
        } catch {
            throw PackError.copyFailed(error.localizedDescription)
        }
        var destination = managed.appendingPathComponent(name, isDirectory: true)
        var n = 2
        while fm.fileExists(atPath: destination.path) {
            destination = managed.appendingPathComponent("\(name) \(n)", isDirectory: true)
            n += 1
        }
        do {
            try fm.copyItem(at: packFolder, to: destination)
        } catch {
            try? fm.removeItem(at: destination)
            throw PackError.copyFailed(error.localizedDescription)
        }
        return destination
    }

    /// Keeps letters, digits, space, ".", "_" and "-"; everything else becomes "_".
    /// Never empty and never hidden (no leading dot).
    static func sanitize(_ raw: String) -> String {
        let mapped = String(raw.map { c -> Character in
            if c.isLetter || c.isNumber || c == " " || c == "." || c == "_" || c == "-" { return c }
            return "_"
        })
        var trimmed = mapped.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasPrefix(".") { trimmed.removeFirst() }
        trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Pack" : trimmed
    }
}
