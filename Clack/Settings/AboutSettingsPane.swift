import SwiftUI
import AppKit

struct AboutSettingsPane: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: DS.Space.s) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text("Clack")
                .font(DS.Typo.aboutTitle)
            Text(version)
                .font(DS.Typo.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("Mechanical keyboard sounds for your Mac.")
                .font(DS.Typo.body)
                .foregroundStyle(.secondary)
                .padding(.top, DS.Space.xs)
            Text("Plays sound packs made for Mechvibes.")
                .font(DS.Typo.caption)
                .foregroundStyle(.tertiary)
        }
        .multilineTextAlignment(.center)
        .frame(width: DS.Size.settingsWidth, height: 320)
    }
}
