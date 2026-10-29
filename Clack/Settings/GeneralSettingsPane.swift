import SwiftUI

struct GeneralSettingsPane: View {
    @State private var launchAtLogin = false
    @State private var needsApproval = false
    @State private var loginError: String?

    private var model: AppModel { .shared }
    private var isInApplications: Bool { Bundle.main.bundlePath.hasPrefix("/Applications") }

    var body: some View {
        @Bindable var preferences = model.preferences

        Section {
            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLogin },
                set: { setLaunchAtLogin($0) }))
            Toggle(isOn: $preferences.startHidden) {
                Text("Start hidden")
                Text("When Clack opens at login, it stays in the menu bar.")
            }
            .disabled(!launchAtLogin)
            if needsApproval {
                LabeledContent("Approve Clack in System Settings to finish.") {
                    Button("Open Login Items") { LaunchAtLogin.openLoginItemsSettings() }
                }
            }
            Toggle(isOn: $preferences.showMenuBarIcon) {
                Text("Show menu bar icon")
                if !preferences.showMenuBarIcon {
                    Text("Open Clack from Finder or Spotlight to see this window.")
                }
            }
            LabeledContent {
                ShortcutRecorder(combo: $preferences.muteShortcut)
            } label: {
                Text("Mute shortcut")
                Text("Works in any app.")
            }
            LabeledContent("Input Monitoring") {
                if model.permission.inputMonitoringGranted {
                    Label("Allowed", systemImage: "checkmark.circle.fill")
                        .font(DS.Typo.body)
                        .foregroundStyle(DS.Palette.success)
                } else {
                    Button("Open Settings") { model.permission.request() }
                }
            }
        } header: {
            Text("General")
        } footer: {
            if loginError != nil || !isInApplications {
                VStack(alignment: .leading, spacing: 4) {
                    if let loginError {
                        Text(loginError)
                    }
                    if !isInApplications {
                        Text("Move Clack to the Applications folder so it opens at login reliably.")
                    }
                }
                .font(DS.Typo.caption)
                .foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: refreshLoginState)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            try LaunchAtLogin.set(on)
            loginError = nil
        } catch {
            loginError = "Couldn't change the login item: \(error.localizedDescription)"
        }
        refreshLoginState()
    }

    private func refreshLoginState() {
        launchAtLogin = LaunchAtLogin.isEnabled
        needsApproval = LaunchAtLogin.needsApproval
    }
}
