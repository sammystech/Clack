import SwiftUI

/// The three essentials: pack, volume, mute. `.floating` wears its own Liquid Glass
/// (main window); `.embedded` is plain because it sits inside the glass menu bar panel.
struct ControlsCluster: View {
    enum Style { case floating, embedded }

    @Environment(AppModel.self) private var model
    private let style: Style

    init(style: Style) {
        self.style = style
    }

    private var rowPadding: CGFloat { style == .floating ? DS.Space.l : DS.Space.xs }

    var body: some View {
        switch style {
        case .floating:
            GlassEffectContainer(spacing: DS.Space.m) {
                rows
                    .glassEffect(.regular, in: .rect(cornerRadius: DS.Radius.cluster))
            }
        case .embedded:
            rows
        }
    }

    private var rows: some View {
        VStack(spacing: 0) {
            packRow
            Divider()
                .padding(.leading, rowPadding)
            volumeRow
        }
    }

    // MARK: Pack

    private var packBinding: Binding<String> {
        Binding(
            get: { model.preferences.selectedPackID },
            set: { model.selectPack(id: $0) })
    }

    private var packRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text("Pack")
                .font(DS.Typo.body)
                .foregroundStyle(.primary)
            Spacer(minLength: DS.Space.s)
            if model.library.hasScannedOnce {
                Picker("Sound", selection: packBinding) {
                    Section("Built-in") {
                        ForEach(model.library.builtIn) { pack in
                            Text(pack.name).tag(pack.id)
                        }
                    }
                    if !model.library.custom.isEmpty {
                        Section("Custom") {
                            ForEach(model.library.custom) { pack in
                                Text(pack.name).tag(pack.id)
                            }
                        }
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .menuIndicator(.visible)
                .frame(maxWidth: DS.Size.pickerMaxWidth, alignment: .trailing)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(height: DS.Size.rowHeight)
        .padding(.horizontal, rowPadding)
    }

    // MARK: Volume and mute

    private var volume: Double { model.preferences.volume }
    private var isMuted: Bool { model.preferences.isMuted }
    private var percent: Int { Int((volume * 100).rounded()) }

    /// Snaps to 5% steps without drawing tick marks on the slider.
    private var volumeBinding: Binding<Double> {
        Binding(
            get: { min(model.preferences.volume, model.maxVolume) },
            set: { newValue in
                let snapped = (newValue / 0.05).rounded() * 0.05
                model.preferences.volume = min(max(snapped, 0), model.maxVolume)
            })
    }

    private var speakerSymbol: String {
        if isMuted { return "speaker.slash.fill" }
        switch volume {
        case ..<0.001: return "speaker.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    private var muteHelp: String {
        let base = isMuted ? "Unmute" : "Mute"
        if let shortcut = model.preferences.muteShortcut?.displayString, !shortcut.isEmpty {
            return "\(base) (\(shortcut))"
        }
        return base
    }

    private var volumeRow: some View {
        HStack(spacing: 10) {
            Button {
                model.toggleMute()
            } label: {
                ZStack {
                    if isMuted {
                        Circle().fill(DS.Palette.accent)
                    }
                    Image(systemName: speakerSymbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isMuted ? Color.white : Color.primary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: DS.Size.iconButton, height: DS.Size.iconButton)
                .contentShape(Circle())
            }
            .buttonStyle(.borderless)
            .help(muteHelp)
            .accessibilityLabel(isMuted ? "Unmute" : "Mute")

            Slider(value: volumeBinding, in: 0...model.maxVolume)
                .tint(volume > 1.0 ? DS.Palette.boostTint : DS.Palette.accent)
                .opacity(isMuted ? 0.5 : 1)
                .accessibilityLabel("Volume")
                .accessibilityValue("\(percent) percent")

            Text(verbatim: "\(percent)%")
                .font(DS.Typo.value)
                .foregroundStyle(.secondary)
                .frame(width: DS.Size.valueLabelWidth, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .frame(height: DS.Size.rowHeight)
        .padding(.horizontal, rowPadding)
    }
}
