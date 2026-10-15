import AppKit
import CoreGraphics
import Observation

/// Tracks the Input Monitoring (listen event) permission.
@MainActor @Observable final class PermissionMonitor {
    private(set) var inputMonitoringGranted: Bool

    /// Called only on transitions (granted <-> not granted). AppModel wires this.
    @ObservationIgnored var onChange: (@MainActor (Bool) -> Void)?

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var isPolling = false

    private static let requestedKey = "didRequestListenAccess"

    init() {
        inputMonitoringGranted = CGPreflightListenEventAccess()
    }

    func refresh() {
        let granted = CGPreflightListenEventAccess()
        guard granted != inputMonitoringGranted else { return }
        inputMonitoringGranted = granted
        if isPolling { scheduleTimer() }
        onChange?(granted)
    }

    /// Shows the system prompt once, then always opens System Settings.
    func request() {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: Self.requestedKey) {
            _ = CGRequestListenEventAccess()
            defaults.set(true, forKey: Self.requestedKey)
        }
        openSystemSettings()
    }

    func openSystemSettings() {
        let modern = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent")!
        if NSWorkspace.shared.open(modern) { return }
        let legacy = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(legacy)
    }

    /// Polls every 1 s while not granted and every 3 s while granted.
    func startPolling() {
        isPolling = true
        scheduleTimer()
    }

    func stopPolling() {
        isPolling = false
        timer?.invalidate()
        timer = nil
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let interval: TimeInterval = inputMonitoringGranted ? 3.0 : 1.0
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
