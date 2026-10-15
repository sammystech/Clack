import SwiftUI

/// Root of the standard Settings scene: General, Sound, Packs, About.
struct SettingsRootView: View {
    @AppStorage("settingsTab") private var selection = "general"

    var body: some View {
        TabView(selection: $selection) {
            GeneralSettingsPane()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag("general")
            SoundSettingsPane()
                .tabItem { Label("Sound", systemImage: "speaker.wave.2") }
                .tag("sound")
            PacksSettingsPane()
                .tabItem { Label("Packs", systemImage: "square.stack.3d.up") }
                .tag("packs")
            AboutSettingsPane()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag("about")
        }
        .environment(AppModel.shared)
    }
}
