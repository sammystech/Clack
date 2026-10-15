import SwiftUI

struct GeneralSettingsPane: View {
    @State private var launchAtLogin = false
    @State private var needsApproval = false
    @State private var loginError: String?

    private var model: AppModel { .shared }
    private var isInApplications: Bool { Bundle.main.bundlePath.hasPrefix("/Applications") }

    var body: some View {
        @Bindable var preferences = model.preferences

        Form {
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
            } header: {
                Text("Startup")
            } footer: {
                if loginError != nil || !isInApplications {
                    VStack(alignment: .leading, spacing: 4) {
                        if let loginError {
                            Text(loginError)
                                .foregroundStyle(.secondary)
                        }
                        if !isInApplications {
                            Text("Move Clack to the Applications folder so it opens at login reliably.")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .font(DS.Typo.caption)
                }
            }

            Section {
                Toggle("Show menu bar icon", isOn: $preferences.showMenuBarIcon)
            } header: {
                Text("Menu Bar")
            } footer: {
                if !preferences.showMenuBarIcon {
                    Text("Open Clack again from Finder or Spotlight to see its window.")
                        .font(DS.Typo.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent("Mute shortcut") {
                    ShortcutRecorder(combo: $preferences.muteShortcut)
                }
            } header: {
                Text("Shortcut")
            } footer: {
                Text("Works in any app, even while Clack is muted.")
                    .font(DS.Typo.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permission") {
                LabeledContent("Input Monitoring") {
                    if model.permission.inputMonitoringGranted {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .font(DS.Typo.body)
                            .foregroundStyle(DS.Palette.success)
                    } else {
                        HStack(spacing: 8) {
                            Text("Not allowed")
                                .foregroundStyle(.secondary)
                            Button("Open Settings") { model.permission.request() }
                        }
                    }
                }
                Button("Show Welcome Again") {
                    model.showOnboarding = true
                    model.requestMainWindow?()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: DS.Size.settingsWidth, height: 470)
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
