import SwiftUI

/// Shown when Clack can't hear the keyboard (or needs a relaunch to finish).
/// The parent decides when it is visible and animates its insertion.
struct PermissionBanner: View {
    enum Style { case regular, compact }

    private let style: Style
    private var model: AppModel { .shared }

    init(style: Style) {
        self.style = style
    }

    var body: some View {
        switch style {
        case .regular: regular
        case .compact: compact
        }
    }

    // MARK: - Content

    private var needsRelaunch: Bool { model.tapNeedsRelaunch }
    private var title: String { needsRelaunch ? "Almost done" : "Clack can't hear your keyboard" }
    private var subtitle: String {
        needsRelaunch ? "Relaunch Clack to finish turning on Input Monitoring."
                      : "Allow Input Monitoring to play sounds."
    }
    private var buttonTitle: String { needsRelaunch ? "Relaunch" : "Grant Access" }

    private func performAction() {
        if needsRelaunch {
            model.relaunch()
        } else {
            model.requestInputAccess()
        }
    }

    private var icon: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 15))
            .foregroundStyle(DS.Palette.warning)
            .accessibilityHidden(true)
    }

    // MARK: - Styles

    /// Floats over the main window's stage, so it is glass.
    private var regular: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(DS.Typo.bodyEmphasized)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(DS.Typo.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Button(buttonTitle, action: performAction)
                .buttonStyle(.glassProminent)
                .controlSize(.small)
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: DS.Radius.banner))
    }

    /// Lives inside the glass menu bar panel, so no glass here.
    private var compact: some View {
        HStack(spacing: 10) {
            icon
            Text(title)
                .font(DS.Typo.bodyEmphasized)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Button(buttonTitle, action: performAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(8)
        .background(DS.Palette.warning.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous))
    }
}
