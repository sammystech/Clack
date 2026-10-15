import AppKit
import Foundation
import Observation

enum PackState: Equatable, Sendable { case loading, ready, failed(String) }
enum ListeningStatus: Sendable { case listening, muted, noAccess }

/// The hub. The only object the UI talks to. Wires preferences, packs, permission,
/// the key tap and the sound engine together.
@MainActor @Observable final class AppModel {
    static let shared = AppModel()

    let preferences: Preferences
    let library: PackLibrary
    let permission: PermissionMonitor
    let keyActivity: KeyActivity

    private(set) var packState: PackState = .ready
    private(set) var activePackID: String?
    var showOnboarding = false
    private(set) var tapNeedsRelaunch = false
    private(set) var isListening = false

    @ObservationIgnored var requestMainWindow: (@MainActor () -> Void)?

    @ObservationIgnored private let engine: SoundEngine
    @ObservationIgnored private let keyMonitor: KeyMonitor
    @ObservationIgnored private let volumeMonitor = SystemVolumeMonitor()
    /// Increments for every pack load; stale completions compare against it and bail.
    @ObservationIgnored private var loadToken = 0
    @ObservationIgnored private var pendingLoadToken: Int?
    /// The pack most recently asked for, so a direct write to preferences.selectedPackID
    /// (for example from Settings) is told apart from selectPack's own write.
    @ObservationIgnored private var requestedPackID: String?
    @ObservationIgnored private var isStarted = false

    private nonisolated static let loadingLabelDelay: Duration = .milliseconds(150)
    private nonisolated static let failedLabelDuration: Duration = .seconds(2)
    private nonisolated static let tapRetryDelay: Duration = .seconds(1)
    private nonisolated static let previewReleaseDelay: Duration = .milliseconds(120)
    private nonisolated static let capsLockReleaseDelay = 0.1
    private nonisolated static let capsLockKeyCode: UInt16 = 0x39

    var listeningStatus: ListeningStatus {
        if !permission.inputMonitoringGranted || (!isListening && !preferences.isMuted && tapNeedsRelaunch) {
            return .noAccess
        }
        return preferences.isMuted ? .muted : .listening
    }

    var canRandomize: Bool { library.all.count >= 2 }

    var maxVolume: Double { preferences.allowBoost ? 2.0 : 1.0 }

    init() {
        let preferences = Preferences()
        let engine = SoundEngine()
        let activity = KeyActivity()
        self.preferences = preferences
        self.library = PackLibrary(preferences: preferences)
        self.permission = PermissionMonitor()
        self.keyActivity = activity
        self.engine = engine
        self.keyMonitor = KeyMonitor { [engine, activity] event in
            // Key-tap thread: sound is scheduled synchronously; only transitions hop to main.
            guard let transition = engine.handle(event) else { return }
            let pressed = transition == .pressed
            let isCapsLock = event.kind == .flagsChanged && event.keyCode == AppModel.capsLockKeyCode
            DispatchQueue.main.async {
                MainActor.assumeIsolated { activity.set(pressed) }
            }
            if pressed && isCapsLock {
                // Caps Lock only reports one flagsChanged per tap, so release the keycap ourselves.
                DispatchQueue.main.asyncAfter(deadline: .now() + AppModel.capsLockReleaseDelay) {
                    MainActor.assumeIsolated {
                        if !engine.hasHeldKeys { activity.set(false) }
                    }
                }
            }
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard !isStarted else { return }
        isStarted = true

        do {
            try engine.start()
        } catch {
            Log.audio.error("Audio engine failed to start: \(error.localizedDescription, privacy: .public)")
        }
        applyGain()
        applyEngineConfig()

        Task {
            await library.rescan()
            let saved = preferences.selectedPackID
            selectPack(id: library.descriptor(id: saved) != nil ? saved : BuiltInPacks.defaultPackID)
            library.startWatching()
            Task.detached(priority: .utility) {
                await BuiltInPacks.preloadAll()
            }
        }

        permission.onChange = { [weak self] granted in
            self?.permissionChanged(granted)
        }
        permission.refresh()
        permission.startPolling()

        if permission.inputMonitoringGranted && !preferences.isMuted {
            startTap()
        }

        HotKeyCenter.shared.register(preferences.muteShortcut) { [weak self] in
            self?.toggleMute()
        }

        volumeMonitor.onChange = { [weak self] in
            self?.applyGain()
        }
        if preferences.constantLoudness {
            volumeMonitor.start()
        }

        preferences.addObserver { [weak self] key in
            self?.handlePreference(key)
        }

        showOnboarding = !permission.inputMonitoringGranted || !preferences.hasCompletedOnboarding
    }

    func shutdown() {
        keyMonitor.stop()
        isListening = false
        engine.shutdown()
        permission.stopPolling()
        volumeMonitor.stop()
    }

    // MARK: - Packs

    func selectPack(id: String) {
        guard let descriptor = library.descriptor(id: id) else {
            if id != BuiltInPacks.defaultPackID {
                selectPack(id: BuiltInPacks.defaultPackID)
            }
            return
        }
        let previous = activePackID
        requestedPackID = id
        if preferences.selectedPackID != id {
            preferences.selectedPackID = id
        }

        loadToken &+= 1
        let token = loadToken
        pendingLoadToken = token

        Task { [weak self] in
            try? await Task.sleep(for: AppModel.loadingLabelDelay)
            guard let self, self.pendingLoadToken == token else { return }
            self.packState = .loading
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                let bank = try await self.library.loadBank(for: descriptor)
                guard token == self.loadToken else { return }
                self.pendingLoadToken = nil
                self.engine.setBank(bank)
                self.activePackID = id
                self.packState = .ready
            } catch {
                guard token == self.loadToken else { return }
                self.pendingLoadToken = nil
                Log.packs.error("Pack failed to load: \(error.localizedDescription, privacy: .public)")
                self.library.recordLoadFailure(packID: id, reason: error.localizedDescription)
                if previous == nil && id != BuiltInPacks.defaultPackID {
                    // Nothing is playing yet: fall back to the default pack instead.
                    self.selectPack(id: BuiltInPacks.defaultPackID)
                    return
                }
                let revert = previous ?? BuiltInPacks.defaultPackID
                self.requestedPackID = revert
                self.preferences.selectedPackID = revert
                let message = "Couldn't load \(descriptor.name)"
                self.packState = .failed(message)
                try? await Task.sleep(for: AppModel.failedLabelDuration)
                if token == self.loadToken && self.packState == .failed(message) {
                    self.packState = .ready
                }
            }
        }
    }

    func randomPack() {
        // No-op with fewer than 2 packs (fixes the original's infinite loop).
        if let id = library.randomPackID(excluding: preferences.selectedPackID) {
            selectPack(id: id)
        }
    }

    func reloadPacks() {
        Task {
            await library.rescan()
            validateSelection()
        }
    }

    /// nil on success, else a user-facing error.
    func importPacks(_ urls: [URL]) async -> String? {
        var last: PackDescriptor?
        for url in urls {
            do {
                last = try await library.importPack(from: url)
            } catch {
                return error.localizedDescription
            }
        }
        if let last {
            selectPack(id: last.id)
        }
        return nil
    }

    func previewSound() {
        guard !preferences.isMuted else { return }
        engine.preview()
        keyActivity.set(true)
        Task { [weak self] in
            try? await Task.sleep(for: AppModel.previewReleaseDelay)
            self?.keyActivity.set(false)
        }
    }

    func openCustomPacksFolder() {
        let folder = library.managedFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    // MARK: - Mute

    func toggleMute() {
        setMuted(!preferences.isMuted)
    }

    func setMuted(_ muted: Bool) {
        // The preferences observer applies it.
        if preferences.isMuted != muted {
            preferences.isMuted = muted
        }
    }

    // MARK: - Permission

    func requestInputAccess() {
        permission.request()
        showOnboarding = true
        requestMainWindow?()
    }

    func relaunch() {
        Task {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            configuration.arguments = ["--relaunch"]
            do {
                _ = try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
                quitClosingSheets()
            } catch {
                Log.ui.error("Relaunch failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// AppKit refuses to quit while a sheet is attached (System Settings' "Quit & Reopen"
    /// after granting Input Monitoring hits this during onboarding). Close sheets first.
    func quitClosingSheets() {
        showOnboarding = false
        for window in NSApp.windows {
            if let sheet = window.attachedSheet { window.endSheet(sheet) }
        }
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }

    // MARK: - Private

    private func handlePreference(_ key: Preferences.Key) {
        switch key {
        case .volume, .allowBoost:
            applyGain()
        case .constantLoudness:
            if preferences.constantLoudness {
                volumeMonitor.start()
            } else {
                volumeMonitor.stop()
            }
            applyGain()
        case .playOnAutoRepeat, .playKeyUpSounds:
            applyEngineConfig()
        case .isMuted:
            applyMute()
        case .muteShortcut:
            HotKeyCenter.shared.register(preferences.muteShortcut) { [weak self] in
                self?.toggleMute()
            }
        case .customPackFolders:
            Task {
                await library.rescan()
                validateSelection()
            }
        case .selectedPackID:
            // Written directly (not via selectPack): load it.
            if preferences.selectedPackID != requestedPackID {
                selectPack(id: preferences.selectedPackID)
            }
        default:
            break
        }
    }

    private func applyEngineConfig() {
        engine.updateConfig(SoundEngine.Config(
            playOnAutoRepeat: preferences.playOnAutoRepeat,
            playKeyUpSounds: preferences.playKeyUpSounds))
    }

    private func applyGain() {
        let volume = min(max(preferences.volume, 0), maxVolume)
        var multiplier = 1.0
        if preferences.constantLoudness {
            let system = Double(volumeMonitor.volume)
            if !volumeMonitor.isMuted && system > 0 {
                multiplier = min(4, max(1, 1 / max(system, 0.25)))
            }
        }
        engine.setGain(volume * multiplier)
    }

    private func applyMute() {
        if preferences.isMuted {
            keyMonitor.stop()
            isListening = false
            engine.resetHeldKeys()
            engine.pauseAudio()
            keyActivity.set(false)
        } else if permission.inputMonitoringGranted {
            // Audio restarts on the first sound.
            startTap()
        }
    }

    private func startTap(isRetry: Bool = false) {
        guard !preferences.isMuted else { return }
        if keyMonitor.start() {
            isListening = true
            tapNeedsRelaunch = false
            return
        }
        isListening = false
        if !isRetry {
            Task { [weak self] in
                try? await Task.sleep(for: AppModel.tapRetryDelay)
                guard let self, !self.isListening, !self.preferences.isMuted,
                      self.permission.inputMonitoringGranted else { return }
                self.startTap(isRetry: true)
            }
        } else if permission.inputMonitoringGranted {
            // Granted but the tap still cannot be created: macOS wants a fresh process.
            tapNeedsRelaunch = true
            Log.input.error("Event tap could not be created although Input Monitoring is granted")
        }
    }

    private func permissionChanged(_ granted: Bool) {
        if granted {
            if !preferences.isMuted { startTap() }
        } else {
            keyMonitor.stop()
            isListening = false
            engine.resetHeldKeys()
            keyActivity.set(false)
            showOnboarding = true
            requestMainWindow?()
        }
    }

    /// After a rescan, fall back to the default pack if the selected one vanished.
    private func validateSelection() {
        if library.descriptor(id: preferences.selectedPackID) == nil {
            selectPack(id: BuiltInPacks.defaultPackID)
        }
    }
}
