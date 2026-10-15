import SwiftUI

/// Content of the menu bar panel. The root carries the only glass; everything inside
/// is plain so glass never stacks on glass.
struct MenuBarPanelView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.closeMenuBarPanel) private var closePanel
    @State private var appeared = false

    private var showBanner: Bool {
        model.listeningStatus == .noAccess || model.tapNeedsRelaunch
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            header
            if showBanner {
                PermissionBanner(style: .compact)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -6)))
            }
            ControlsCluster(style: .embedded)
            footer
        }
        .padding(DS.Space.m)
        .frame(width: DS.Size.menuPanelWidth)
        .glassEffect(.regular, in: .rect(cornerRadius: DS.Radius.panel))
        .scaleEffect(appeared || reduceMotion ? 1 : 0.96, anchor: .top)
        .animation(reduceMotion ? DS.Motion.reducedFade : DS.Motion.banner, value: showBanner)
        .onAppear {
            guard !reduceMotion else { appeared = true; return }
            withAnimation(DS.Motion.panel) { appeared = true }
        }
    }

    // MARK: Header

    /// The panel has no keycap, so a failed pack switch is surfaced here for its 2 s.
    private var failureMessage: String? {
        if case .failed(let message) = model.packState { return message }
        return nil
    }

    private var statusText: String {
        if let failureMessage { return failureMessage }
        switch model.listeningStatus {
        case .listening: return "Listening"
        case .muted: return "Muted"
        case .noAccess: return "No access"
        }
    }

    private var statusColor: Color {
        if failureMessage != nil { return DS.Palette.warning }
        switch model.listeningStatus {
        case .listening: return DS.Palette.success
        case .muted: return DS.Palette.idleDot
        case .noAccess: return DS.Palette.warning
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Clack")
                .font(DS.Typo.bodyEmphasized)
            Spacer()
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(statusText)
                .font(DS.Typo.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(height: 22)
        .padding(.horizontal, DS.Space.xs)
        .accessibilityElement(children: .combine)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button {
                closePanel()
                MainWindowController.shared.show()
            } label: {
                Label("Open Clack", systemImage: "macwindow")
                    .font(DS.Typo.caption)
            }
            .buttonStyle(.borderless)

            Spacer()

            Button {
                closePanel()
                SettingsOpener.open()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .frame(width: DS.Size.iconButton - 2, height: DS.Size.iconButton - 2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Settings")
            .accessibilityLabel("Settings")
        }
        .frame(height: 28)
        .padding(.horizontal, DS.Space.xs)
    }
}
