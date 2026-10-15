import SwiftUI
import AppKit

/// The Input Monitoring sheet on the main window. Advances to "done" on its own once
/// access is granted and the tap is running.
struct OnboardingView: View {
    private enum Step: Hashable { case permission, done }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounce = 0

    private var model: AppModel { .shared }

    private var step: Step {
        // Muted means no tap by design, so access alone is enough to finish.
        model.permission.inputMonitoringGranted
            && (model.isListening || (model.preferences.isMuted && !model.tapNeedsRelaunch))
            ? .done : .permission
    }

    var body: some View {
        ZStack {
            switch step {
            case .permission: permissionStep.transition(stepTransition)
            case .done: doneStep.transition(stepTransition)
            }
        }
        .animation(reduceMotion ? DS.Motion.reducedFade : DS.Motion.step, value: step)
        .padding(DS.Space.xxl)
        .frame(width: DS.Size.onboardingWidth)
    }

    private var stepTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98))
    }

    // MARK: - Permission

    private var permissionStep: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)

            Text("Let Clack hear your keys")
                .font(DS.Typo.sheetTitle)
                .multilineTextAlignment(.center)

            bodyText("Clack plays a sound for each key you press, in every app. macOS asks you to turn on Input Monitoring before an app can hear key presses.")

            VStack(alignment: .leading, spacing: 10) {
                privacyRow("lock.shield", "Clack never records or saves what you type.")
                privacyRow("wifi.slash", "Clack never connects to the internet.")
                privacyRow("hand.raised", "You can turn it off anytime in System Settings.")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .quaternarySystemFill),
                        in: RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous))

            statusLine

            HStack(spacing: 12) {
                Button("Later") { model.showOnboarding = false }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Open System Settings") { model.permission.request() }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }

            Text("In Privacy & Security, open Input Monitoring and switch on Clack.")
                .font(DS.Typo.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if model.tapNeedsRelaunch {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DS.Palette.success)
                    .accessibilityHidden(true)
                Text("Access is on. Relaunch Clack to finish.")
                    .font(.system(size: 12))
                Button("Relaunch") { model.relaunch() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for access…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func privacyRow(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(text)
                .font(DS.Typo.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Done

    private var doneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(DS.Palette.success)
                .symbolEffect(.bounce, value: bounce)
                .accessibilityHidden(true)
                .task {
                    guard !reduceMotion else { return }
                    try? await Task.sleep(for: .milliseconds(150))
                    bounce += 1
                }

            Text("You're all set")
                .font(DS.Typo.sheetTitle)

            bodyText("Type anywhere to hear Clack. It lives in your menu bar.")

            KeycapView(scale: 0.8)
                .environment(model)
                .padding(.vertical, DS.Space.s)

            Button("Done") {
                model.preferences.hasCompletedOnboarding = true
                model.showOnboarding = false
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func bodyText(_ text: String) -> some View {
        Text(text)
            .font(DS.Typo.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 360)
            .fixedSize(horizontal: false, vertical: true)
    }
}
