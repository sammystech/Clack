import SwiftUI

/// Main window content: a quiet solid stage holding the keycap, with the glass control
/// cluster floating at the bottom and the permission banner floating at the top.
struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var showBanner: Bool {
        model.listeningStatus == .noAccess || model.tapNeedsRelaunch
    }

    private var bannerTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -6))
    }

    var body: some View {
        @Bindable var model = model

        ZStack {
            DS.Palette.stage
                .ignoresSafeArea()
            if !(contrast == .increased || reduceTransparency) {
                RadialGradient(colors: [DS.Palette.stageGlow, .clear],
                               center: UnitPoint(x: 0.5, y: 0.42),
                               startRadius: 0, endRadius: 220)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                if showBanner {
                    PermissionBanner(style: .regular)
                        .padding(.horizontal, DS.Space.l)
                        .padding(.top, DS.Space.s)
                        .transition(bannerTransition)
                }
                Spacer(minLength: 24)
                KeycapView()
                Spacer(minLength: 24)
                ControlsCluster(style: .floating)
                    .padding([.horizontal, .bottom], DS.Space.l)
            }
        }
        .frame(minWidth: DS.Size.mainWindowMin.width, minHeight: DS.Size.mainWindowMin.height)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // AppKit-hosted window: open Settings through the app menu item,
                // which works whether or not Clack is the active app.
                Button {
                    SettingsOpener.open()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings (⌘,)")
            }
        }
        .sheet(isPresented: $model.showOnboarding) {
            OnboardingView()
                .environment(model)
        }
        .animation(reduceMotion ? DS.Motion.reducedFade : DS.Motion.banner, value: showBanner)
    }
}
