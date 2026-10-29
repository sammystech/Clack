import SwiftUI

struct SoundSettingsPane: View {
    @AppStorage("showKeysOnKeycap") private var showKeys = true
    @AppStorage("speakKeys") private var speakKeys = false
    private var model: AppModel { .shared }

    var body: some View {
        @Bindable var preferences = model.preferences

        Group {
            Section("Typing") {
                Toggle(isOn: $preferences.playKeyUpSounds) {
                    Text("Key-up sounds")
                    Text("Plays a release sound when the pack has one.")
                }
                Toggle(isOn: $preferences.playOnAutoRepeat) {
                    Text("Play on held-key repeat")
                    Text("Off: a held key plays once.")
                }
                Toggle(isOn: $preferences.allowBoost) {
                    Text("Volume above 100%")
                    Text("Lets the volume go up to 200%.")
                }
                Toggle(isOn: $preferences.constantLoudness) {
                    Text("Keep loudness constant")
                    Text("Makes Clack louder when your Mac's volume is low, up to 4 times.")
                }
                Toggle(isOn: $showKeys) {
                    Text("Show keys on the keycap")
                    Text("The keycap shows each key you press.")
                }
                Toggle(isOn: $speakKeys) {
                    Text("Say keys out loud")
                    Text("Speaks every key you press. Fast typing overlaps. Just for fun.")
                }
                .onChange(of: speakKeys) { _, on in if on { KeySpeaker.shared.prepare() } }
            }
        }
    }
}
