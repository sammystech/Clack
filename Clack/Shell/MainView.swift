import SwiftUI

/// Clack's one window: the keycap stage at the top, then every setting below it on a
/// single scrolling page (sound, typing, packs, general, updates). There is no separate
/// Settings window; ⌘, and the menu bar's Settings item open this.
struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showBanner: Bool {
        model.listeningStatus == .noAccess || model.tapNeedsRelaunch
    }

    var body: some View {
        @Bindable var model = model

        Form {
            if showBanner {
                Section {
                    PermissionBanner(style: .regular)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section("Sound") {
                ControlsCluster(style: .embedded)
            }
            SoundSettingsPane()
            PacksSettingsPane()
            GeneralSettingsPane()
            UpdatesSection()
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 0, for: .scrollContent)
        // The keycap stays pinned above the settings so you can test sounds while changing them.
        .safeAreaInset(edge: .top, spacing: 0) {
            HeroView()
        }
        .background(StageBackground())
        .frame(minWidth: DS.Size.mainWindowMin.width, minHeight: DS.Size.mainWindowMin.height)
        .onAppear { model.reloadPacks() }
        .sheet(isPresented: $model.showOnboarding) {
            OnboardingView()
                .environment(model)
        }
        .animation(reduceMotion ? DS.Motion.reducedFade : DS.Motion.banner, value: showBanner)
    }
}

/// Window background: the solid stage with a soft accent-tinted glow behind the keycap.
private struct StageBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack(alignment: .top) {
            DS.Palette.stage
            if !(contrast == .increased || reduceTransparency) {
                RadialGradient(colors: [DS.Palette.accent.opacity(0.10), .clear],
                               center: UnitPoint(x: 0.5, y: 0.0),
                               startRadius: 0, endRadius: 320)
                    .frame(height: 360)
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }
}

/// The keycap plus a one-line status: what Clack is doing right now.
private struct HeroView: View {
    @Environment(AppModel.self) private var model

    private var packName: String {
        model.library.all.first { $0.id == model.preferences.selectedPackID }?.name ?? "Clack"
    }

    private var status: (text: String, color: Color) {
        switch model.listeningStatus {
        case .listening: ("Listening · \(packName)", DS.Palette.success)
        case .muted: ("Muted", DS.Palette.accent)
        case .noAccess: ("Needs Input Monitoring", DS.Palette.warning)
        }
    }

    var body: some View {
        VStack(spacing: DS.Space.l) {
            KeycapView(scale: 1.1)
            HStack(spacing: 6) {
                Circle()
                    .fill(status.color)
                    .frame(width: 7, height: 7)
                Text(status.text)
                    .font(DS.Typo.captionEmphasized)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, DS.Space.m)
            .padding(.vertical, 5)
            .glassEffect(.regular, in: .capsule)
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DS.Space.xxl + DS.Space.l)   // clears the transparent title bar
        .padding(.bottom, DS.Space.l)
        .background(alignment: .bottom) {
            // Opaque, so settings scroll away beneath it; a fade softens the edge.
            StageBackground()
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, DS.Palette.stage], startPoint: .top, endPoint: .bottom)
                        .frame(height: DS.Space.l)
                        .offset(y: DS.Space.l)
                }
        }
    }
}

/// Check for updates right here; the result shows inline, a new version opens the installer.
private struct UpdatesSection: View {
    @AppStorage(Updater.autoInstallKey) private var autoInstall = true
    private var updater: Updater { .shared }

    private var detail: String {
        if updater.checking { return "Checking…" }
        if let result = updater.lastResult { return result }
        if let last = updater.lastChecked {
            return "Last checked \(last.formatted(.relative(presentation: .named)))."
        }
        return "Not checked yet."
    }

    var body: some View {
        Section {
            HStack(spacing: DS.Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clack \(updater.currentVersion)")
                        .font(DS.Typo.bodyEmphasized)
                    Text(detail)
                        .font(DS.Typo.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
                Spacer()
                if updater.checking {
                    ProgressView().controlSize(.small)
                }
                Button("Check for Updates") { updater.checkInline() }
                    .disabled(updater.checking)
            }
            .padding(.vertical, DS.Space.xxs)
            Toggle(isOn: $autoInstall) {
                Text("Install updates automatically")
                Text("Clack checks every few hours and relaunches itself on a new version.")
            }
        } header: {
            Text("Updates")
        } footer: {
            VStack(spacing: 2) {
                Text("Mechanical keyboard sounds for your Mac.")
                Text("Plays sound packs made for Mechvibes.")
                    .foregroundStyle(.tertiary)
            }
            .font(DS.Typo.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, DS.Space.l)
        }
    }
}
