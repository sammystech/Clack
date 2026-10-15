import Foundation

/// A Mechvibes `config.json`, parsed leniently. Parsing never touches audio.
struct MechvibesConfig: Sendable {
    enum DefineType: Sendable { case single, multi }
    enum Define: Sendable, Hashable {
        case sprite(startMs: Double, durationMs: Double)
        case file(String)
    }

    var name: String
    var version: Int
    var defineType: DefineType
    var sound: String?
    var soundUp: String?
    var down: [Int: Define]
    var up: [Int: Define]

    var hasKeyUp: Bool { !up.isEmpty || (soundUp?.isEmpty == false) }

    static func parse(data: Data, folderName: String) throws -> MechvibesConfig {
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: bytes)
        } catch {
            // Second chance for hand-edited packs (trailing commas, comments).
            do {
                object = try JSONSerialization.jsonObject(with: bytes, options: [.json5Allowed])
            } catch {
                throw PackError.invalidJSON(error.localizedDescription)
            }
        }
        guard let root = object as? [String: Any] else {
            throw PackError.invalidJSON("top level is not an object")
        }

        // version
        var version = 1
        if let raw = root["version"], !(raw is NSNull) {
            if let n = number(raw) { version = Int(n) }
        }
        guard version == 1 || version == 2 else { throw PackError.unsupportedVersion(version) }

        // key_define_type
        let typeString = (root["key_define_type"] as? String)?.trimmingCharacters(in: .whitespaces).lowercased()
        let defineType: DefineType = typeString == "multi" ? .multi : .single

        // name
        let rawName = (root["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = rawName.isEmpty ? folderName : rawName

        // sound / soundup
        func nonEmptyString(_ key: String) -> String? {
            guard let s = root[key] as? String else { return nil }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        let sound = nonEmptyString("sound")
        let soundUp = nonEmptyString("soundup")

        // defines
        guard let defines = root["defines"] as? [String: Any] else {
            throw PackError.missingField("defines")
        }
        var down: [Int: Define] = [:]
        var up: [Int: Define] = [:]
        for (rawKey, value) in defines {
            if value is NSNull { continue }
            let key = rawKey.trimmingCharacters(in: .whitespaces)
            let isUp: Bool
            let code: Int
            if key.lowercased().hasSuffix("-up"), let c = Int(key.dropLast(3)) {
                isUp = true; code = c
            } else if let c = Int(key) {
                isUp = false; code = c
            } else {
                continue
            }

            let define: Define
            switch defineType {
            case .single:
                guard let pair = value as? [Any], pair.count >= 2,
                      let start = number(pair[0]), let duration = number(pair[1]) else { continue }
                define = .sprite(startMs: start, durationMs: duration)
            case .multi:
                guard let file = value as? String else { continue }
                let trimmed = file.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                define = .file(trimmed)
            }
            if isUp { up[code] = define } else { down[code] = define }
        }

        if defineType == .single, sound == nil {
            throw PackError.missingField("sound")
        }

        return MechvibesConfig(
            name: name, version: version, defineType: defineType,
            sound: sound, soundUp: soundUp, down: down, up: up)
    }

    /// Accepts JSON numbers and numeric strings. Booleans are rejected.
    private static func number(_ value: Any) -> Double? {
        if let n = value as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
            let d = n.doubleValue
            return d.isFinite ? d : nil
        }
        if let s = value as? String, let d = Double(s.trimmingCharacters(in: .whitespaces)), d.isFinite {
            return d
        }
        return nil
    }
}

// MARK: - Cheap validation (shared by scanning and import)

extension MechvibesConfig {
    /// Validates without decoding audio. Throws the first problem found.
    func validate(in folder: URL) throws {
        if down.isEmpty && up.isEmpty { throw PackError.noKeysDefined }
        switch defineType {
        case .single:
            guard let sound, !PackFileResolver.resolve(sound, in: folder).isEmpty else {
                throw PackError.missingSoundFile(sound ?? "sound")
            }
        case .multi:
            var names: [String] = []
            for define in down.values { if case .file(let f) = define { names.append(f) } }
            for define in up.values { if case .file(let f) = define { names.append(f) } }
            if let sound { names.append(sound) }
            if let soundUp { names.append(soundUp) }
            var checked = Set<String>()
            for name in names where checked.insert(name).inserted {
                if !PackFileResolver.resolve(name, in: folder).isEmpty { return }
            }
            throw PackError.noSoundsFound
        }
    }

    /// Reads, parses and validates a pack's config.json.
    static func load(configURL: URL) throws -> MechvibesConfig {
        let folder = configURL.deletingLastPathComponent()
        let data: Data
        do {
            data = try Data(contentsOf: configURL)
        } catch {
            throw PackError.noConfig
        }
        let config = try parse(data: data, folderName: folder.lastPathComponent)
        try config.validate(in: folder)
        return config
    }
}

// MARK: - File resolution

nonisolated enum PackFileResolver {
    /// Maximum number of files a `{a-b}` pattern may expand to.
    static let maxPatternRange = 64

    /// Resolves a sound file reference relative to the pack folder.
    /// Rejects absolute paths and `..` components. `{a-b}` expands to every existing match.
    /// Returns an empty array when nothing resolves.
    static func resolve(_ reference: String, in folder: URL) -> [URL] {
        let normalized = reference.replacingOccurrences(of: "\\", with: "/")
        guard !normalized.isEmpty, !normalized.hasPrefix("/"), !normalized.hasPrefix("~") else { return [] }
        let components = normalized.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.isEmpty, !components.contains("..") else { return [] }

        var results: [URL] = []
        for candidate in expand(normalized) {
            if let url = resolveSingle(candidate, in: folder), !results.contains(url) {
                results.append(url)
            }
        }
        return results
    }

    private static func expand(_ name: String) -> [String] {
        guard let match = name.firstMatch(of: /\{(\d+)-(\d+)\}/),
              let a = Int(match.output.1), let b = Int(match.output.2),
              b >= a, b - a + 1 <= maxPatternRange else {
            return [name]
        }
        return (a...b).map { name.replacingCharacters(in: match.range, with: String($0)) }
    }

    private static func resolveSingle(_ relative: String, in folder: URL) -> URL? {
        let fm = FileManager.default
        let exact = folder.appendingPathComponent(relative)
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: exact.path, isDirectory: &isDir), !isDir.boolValue {
            return exact
        }
        // Case-insensitive basename match in the same directory.
        let parent = exact.deletingLastPathComponent()
        let wanted = exact.lastPathComponent.lowercased()
        guard let names = try? fm.contentsOfDirectory(atPath: parent.path),
              let hit = names.first(where: { $0.lowercased() == wanted }) else { return nil }
        let url = parent.appendingPathComponent(hit)
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { return nil }
        return url
    }
}
