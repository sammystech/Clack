import SwiftUI

struct SoundSettingsPane: View {
    private var model: AppModel { .shared }

    var body: some View {
        @Bindable var preferences = model.preferences
        let percent = Int((preferences.volume * 100).rounded())

        Form {
            Section("Volume") {
                LabeledContent("Volume") {
                    HStack(spacing: 10) {
                        Slider(value: $preferences.volume, in: 0...model.maxVolume) {   // Preferences snaps to 5%; no tick marks
                            Text("Volume")
                        }
                        .labelsHidden()
                        .tint(preferences.volume > 1 ? DS.Palette.boostTint : DS.Palette.accent)
                        .accessibilityValue("\(percent)%")
                        Text("\(percent)%")
                            .font(DS.Typo.value)
                            .foregroundStyle(.secondary)
                            .frame(width: DS.Size.valueLabelWidth, alignment: .trailing)
                            .accessibilityHidden(true)
                    }
                }
            }

            Section("Playback") {
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
            }
        }
        .formStyle(.grouped)
        .frame(width: DS.Size.settingsWidth, height: 380)
    }
}
