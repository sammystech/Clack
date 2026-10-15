import SwiftUI

/// The signature keycap (content layer, never glass). Sinks 2pt on every key press;
/// clicking it previews the current pack.
struct KeycapView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private let scale: CGFloat

    init(scale: CGFloat = 1.0) {
        self.scale = scale
    }

    @AppStorage("showKeysOnKeycap") private var showKeys = true

    private var isMuted: Bool { model.preferences.isMuted }

    private var label: String {
        if isMuted { return "Muted" }
        switch model.packState {
        case .loading: return "Loading…"
        case .failed: return "Failed"
        case .ready: return (showKeys ? model.keyActivity.lastKey : nil) ?? "Clack"
        }
    }

    var body: some View {
        let footprint = CGSize(width: DS.Size.keycap.width, height: DS.Size.keycap.height + DS.Size.keycapLip)
        Button {
            model.previewSound()
        } label: {
            Text(label)
        }
        .buttonStyle(KeycapButtonStyle(
            label: label,
            externallyPressed: model.keyActivity.isPressed,
            isMuted: isMuted,
            reduceMotion: reduceMotion,
            increaseContrast: contrast == .increased))
        .scaleEffect(scale)
        .frame(width: footprint.width * scale, height: footprint.height * scale)
        .accessibilityLabel(isMuted ? "Clack is muted" : "Test sound")
        .accessibilityHint("Plays the current sound pack")
    }
}

private struct KeycapButtonStyle: ButtonStyle {
    let label: String
    let externallyPressed: Bool
    let isMuted: Bool
    let reduceMotion: Bool
    let increaseContrast: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = externallyPressed || configuration.isPressed
        let travel = (pressed && !reduceMotion) ? DS.Space.xxs : 0
        let shape = RoundedRectangle(cornerRadius: DS.Radius.keycap, style: .continuous)
        let lipOpacity: Double = isMuted ? 0 : ((reduceMotion && pressed) ? 0 : 1)

        return ZStack(alignment: .top) {
            // (a) accent lip, peeks out 2pt below the face at rest.
            shape
                .fill(DS.Palette.accent)
                .frame(width: DS.Size.keycap.width, height: DS.Size.keycap.height)
                .offset(y: DS.Size.keycapLip)
                .opacity(lipOpacity)

            // (b) face with stroke, inner top highlight and (c) label.
            ZStack {
                shape
                    .fill(DS.Palette.keycapFace)
                    .dsShadow(pressed ? DS.Shadow.keycapPressed : DS.Shadow.keycapRest)
                shape
                    .strokeBorder(increaseContrast ? DS.Palette.keycapStrokeHigh : DS.Palette.keycapStroke,
                                  lineWidth: 1)
                RoundedRectangle(cornerRadius: DS.Radius.keycap - 1.5, style: .continuous)
                    .stroke(DS.Palette.keycapHighlight, lineWidth: 1)
                    .padding(1.5)
                    .mask(alignment: .top) {
                        Rectangle().frame(height: 8)
                    }
                Text(label)
                    .font(DS.Typo.keycapLabel)
                    .tracking(DS.Typo.keycapTracking)
                    .foregroundStyle(DS.Palette.keycapLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, DS.Space.m)
            }
            .frame(width: DS.Size.keycap.width, height: DS.Size.keycap.height)
            .brightness((reduceMotion && pressed) ? -0.04 : 0)
            .opacity(isMuted ? 0.55 : 1)
            .offset(y: travel)
        }
        .frame(width: DS.Size.keycap.width,
               height: DS.Size.keycap.height + DS.Size.keycapLip,
               alignment: .top)
        .contentShape(shape)
        .animation(reduceMotion ? DS.Motion.keyPressReduced : DS.Motion.keyPress, value: pressed)
    }
}
