import Foundation
import Observation

/// Every user setting Clack stores. Backed by UserDefaults, keys are the property names.
/// Mechvibes' own preferences are never imported.
@MainActor @Observable final class Preferences {
    enum Key: String, CaseIterable {
        case selectedPackID, volume, isMuted, allowBoost, showMenuBarIcon, startHidden,
             constantLoudness, playOnAutoRepeat, playKeyUpSounds, customPackFolders,
             muteShortcut, hasCompletedOnboarding
    }

    var selectedPackID: String { didSet { changed(.selectedPackID) } }

    /// 0...1, or 0...2 while allowBoost is on. Snapped to steps of 0.05.
    var volume: Double {
        didSet {
            let clamped = Self.normalizedVolume(volume, allowBoost: allowBoost)
            if clamped != volume {
                isAdjusting = true
                volume = clamped
                isAdjusting = false
            }
            guard !isAdjusting, volume != oldValue else { return }
            changed(.volume)
        }
    }

    var isMuted: Bool { didSet { changed(.isMuted) } }

    var allowBoost: Bool {
        didSet {
            if !allowBoost && volume > 1 { volume = 1 }
            changed(.allowBoost)
        }
    }

    var showMenuBarIcon: Bool { didSet { changed(.showMenuBarIcon) } }
    var startHidden: Bool { didSet { changed(.startHidden) } }
    var constantLoudness: Bool { didSet { changed(.constantLoudness) } }
    var playOnAutoRepeat: Bool { didSet { changed(.playOnAutoRepeat) } }
    var playKeyUpSounds: Bool { didSet { changed(.playKeyUpSounds) } }

    /// Absolute, standardized, tilde-expanded, deduplicated folder paths.
    var customPackFolders: [String] {
        didSet {
            let normalized = Self.normalizedFolders(customPackFolders)
            if normalized != customPackFolders {
                isAdjusting = true
                customPackFolders = normalized
                isAdjusting = false
            }
            guard !isAdjusting, customPackFolders != oldValue else { return }
            changed(.customPackFolders)
        }
    }

    /// nil means the owner cleared the shortcut.
    var muteShortcut: KeyCombo? { didSet { changed(.muteShortcut) } }

    var hasCompletedOnboarding: Bool { didSet { changed(.hasCompletedOnboarding) } }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var observers: [@MainActor (Key) -> Void] = []
    @ObservationIgnored private var isAdjusting = false

    private struct StoredShortcut: Codable {
        var combo: KeyCombo?
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.selectedPackID.rawValue: "builtin.linear",
            Key.volume.rawValue: 0.5,
            Key.isMuted.rawValue: false,
            Key.allowBoost.rawValue: false,
            Key.showMenuBarIcon.rawValue: true,
            Key.startHidden.rawValue: false,
            Key.constantLoudness.rawValue: false,
            Key.playOnAutoRepeat.rawValue: false,
            Key.playKeyUpSounds.rawValue: true,
            Key.customPackFolders.rawValue: [String](),
            Key.hasCompletedOnboarding.rawValue: false,
        ])

        let boost = defaults.bool(forKey: Key.allowBoost.rawValue)
        selectedPackID = defaults.string(forKey: Key.selectedPackID.rawValue) ?? "builtin.linear"
        allowBoost = boost
        volume = Self.normalizedVolume(defaults.double(forKey: Key.volume.rawValue), allowBoost: boost)
        isMuted = defaults.bool(forKey: Key.isMuted.rawValue)
        showMenuBarIcon = defaults.bool(forKey: Key.showMenuBarIcon.rawValue)
        startHidden = defaults.bool(forKey: Key.startHidden.rawValue)
        constantLoudness = defaults.bool(forKey: Key.constantLoudness.rawValue)
        playOnAutoRepeat = defaults.bool(forKey: Key.playOnAutoRepeat.rawValue)
        playKeyUpSounds = defaults.bool(forKey: Key.playKeyUpSounds.rawValue)
        customPackFolders = Self.normalizedFolders(
            defaults.stringArray(forKey: Key.customPackFolders.rawValue) ?? [])
        hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding.rawValue)

        if let data = defaults.data(forKey: Key.muteShortcut.rawValue),
           let stored = try? JSONDecoder().decode(StoredShortcut.self, from: data) {
            muteShortcut = stored.combo
        } else {
            muteShortcut = KeyCombo.defaultMute
        }
    }

    func addObserver(_ f: @escaping @MainActor (Key) -> Void) {
        observers.append(f)
    }

    // MARK: - Private

    private func changed(_ key: Key) {
        persist(key)
        for observer in observers { observer(key) }
    }

    private func persist(_ key: Key) {
        let name = key.rawValue
        switch key {
        case .selectedPackID: defaults.set(selectedPackID, forKey: name)
        case .volume: defaults.set(volume, forKey: name)
        case .isMuted: defaults.set(isMuted, forKey: name)
        case .allowBoost: defaults.set(allowBoost, forKey: name)
        case .showMenuBarIcon: defaults.set(showMenuBarIcon, forKey: name)
        case .startHidden: defaults.set(startHidden, forKey: name)
        case .constantLoudness: defaults.set(constantLoudness, forKey: name)
        case .playOnAutoRepeat: defaults.set(playOnAutoRepeat, forKey: name)
        case .playKeyUpSounds: defaults.set(playKeyUpSounds, forKey: name)
        case .customPackFolders: defaults.set(customPackFolders, forKey: name)
        case .hasCompletedOnboarding: defaults.set(hasCompletedOnboarding, forKey: name)
        case .muteShortcut:
            if let data = try? JSONEncoder().encode(StoredShortcut(combo: muteShortcut)) {
                defaults.set(data, forKey: name)
            }
        }
    }

    private static func normalizedVolume(_ value: Double, allowBoost: Bool) -> Double {
        let upper = allowBoost ? 2.0 : 1.0
        let finite = value.isFinite ? value : 0.5
        let snapped = (min(max(finite, 0), upper) / 0.05).rounded() * 0.05
        return min(max(snapped, 0), upper)
    }

    private static func normalizedFolders(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in paths {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let expanded = (trimmed as NSString).expandingTildeInPath
            guard expanded.hasPrefix("/") else { continue }
            let path = URL(fileURLWithPath: expanded).standardizedFileURL.path
            if seen.insert(path).inserted { result.append(path) }
        }
        return result
    }
}
