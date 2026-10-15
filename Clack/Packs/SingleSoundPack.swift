import Foundation

/// Builds a Mechvibes "single" pack from one audio file: every key plays the whole file.
/// The loader clips each key's slice to the file's real length, so no duration probe is needed.
enum SingleSoundPack {
    /// Longest slice a key plays, in ms. Keeps a long file from droning on every keystroke.
    static let maxClipMilliseconds = 1500

    static var stagingRoot: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ClackNewSound", isDirectory: true)
    }

    /// Writes a pack folder (named after `name`) to a staging area and returns it, ready for import.
    static func make(from audio: URL, name: String) throws -> URL {
        let fm = FileManager.default
        let folder = stagingRoot.appendingPathComponent(PackImporter.sanitize(name), isDirectory: true)
        try? fm.removeItem(at: folder)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        let soundName = "sound." + audio.pathExtension.lowercased()
        try fm.copyItem(at: audio, to: folder.appendingPathComponent(soundName))

        var scancodes = Set<Int>()
        for keyCode in 0...UInt16(255) {
            scancodes.formUnion(KeyCodeMap.candidates(forKeyCode: keyCode))
        }
        var defines: [String: [Int]] = [:]
        for code in scancodes { defines[String(code)] = [0, maxClipMilliseconds] }

        let config: [String: Any] = [
            "id": "custom-sound-\(Int(Date().timeIntervalSince1970 * 1000))",
            "name": name,
            "key_define_type": "single",
            "includes_numpad": true,
            "sound": soundName,
            "defines": defines,
        ]
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: folder.appendingPathComponent("config.json"))
        return folder
    }
}
