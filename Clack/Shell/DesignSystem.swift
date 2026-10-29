import SwiftUI
import AppKit

/// Clack design tokens. Two layers: a solid content layer (stage, keycap, forms, lists)
/// and a Liquid Glass functional layer (toolbar, control cluster, menu bar panel, sheets,
/// main window banner). Grayscale plus one accent.
enum DS {
    enum Space {            // derived from Mechvibes' scale 2/5/8/10/12/15/20/50 px
        static let xxs: CGFloat = 2   // key travel
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16    // window margins, row padding
        static let xl: CGFloat = 20   // Mechvibes body padding
        static let xxl: CGFloat = 28  // sheet padding
        static let hero: CGFloat = 48 // ~Mechvibes 50px gap under logo
    }

    enum Radius {
        static let chip: CGFloat = 6
        static let row: CGFloat = 10       // compact banner in panel
        static let thumb: CGFloat = 12     // grouped boxes, menu panel inner
        static let keycap: CGFloat = 14
        static let banner: CGFloat = 16
        static let panel: CGFloat = 18     // menu bar panel
        static let cluster: CGFloat = 22   // floating control cluster
    }

    enum Size {
        static let rowHeight: CGFloat = 44
        static let iconButton: CGFloat = 30
        static let keycap = CGSize(width: 196, height: 76)   // original logo ~197x72
        static let keycapLip: CGFloat = 2
        static let mainWindow = CGSize(width: 500, height: 760)
        static let mainWindowMin = CGSize(width: 440, height: 520)
        static let mainWindowMax = CGSize(width: 720, height: 1400)
        static let menuPanelWidth: CGFloat = 300
        static let onboardingWidth: CGFloat = 440
        static let valueLabelWidth: CGFloat = 44
        static let pickerMaxWidth: CGFloat = 190
    }

    enum Typo {
        static let body = Font.system(size: 13)
        static let bodyEmphasized = Font.system(size: 13, weight: .semibold)
        static let caption = Font.system(size: 11)
        static let captionEmphasized = Font.system(size: 11, weight: .medium)
        static let value = Font.system(size: 13).monospacedDigit()
        static let sheetTitle = Font.system(size: 22, weight: .bold)
        static let aboutTitle = Font.system(size: 20, weight: .bold)
        static let keycapLabel = Font.system(size: 26, weight: .semibold, design: .rounded) // tracking -0.3
        static let keycapTracking: CGFloat = -0.3
    }

    enum Palette {
        static let accent = Color("AccentColor")   // #D63A31 light and dark
        static var accentNS: NSColor { NSColor(red: 0xD6 / 255, green: 0x3A / 255, blue: 0x31 / 255, alpha: 1) }
        static let keycapFace = Color(nsColor: dyn(light: 0xFFFFFF, dark: 0x2C2C2E))
        static let keycapStroke = Color(nsColor: dyn(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.10, darkAlpha: 0.12))
        /// Increase Contrast variant of the keycap stroke.
        static let keycapStrokeHigh = Color(nsColor: dyn(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.30, darkAlpha: 0.30))
        static let keycapHighlight = Color(nsColor: dyn(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.9, darkAlpha: 0.07)) // 1pt inner top line
        static let keycapLabel = Color.primary                    // #1D1D1F / #F5F5F7 via system
        static let stage = Color(nsColor: .windowBackgroundColor)
        static let stageGlow = Color.primary.opacity(0.035)       // radial center, removed under Increase Contrast / Reduce Transparency
        static let hairline = Color(nsColor: .separatorColor)
        static let boostTint = Color.orange                       // systemOrange
        static let warning = Color.orange
        static let success = Color.green
        static let idleDot = Color.secondary

        /// Dynamic NSColor that resolves per appearance (dark vs light).
        static func dyn(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> NSColor {
            NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                let hex = isDark ? dark : light
                return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                               green: CGFloat((hex >> 8) & 0xFF) / 255,
                               blue: CGFloat(hex & 0xFF) / 255,
                               alpha: isDark ? darkAlpha : lightAlpha)
            }
        }
    }

    enum Shadow {   // two-layer, never a single hard shadow; (color, radius, y)
        static let keycapRest: [(Color, CGFloat, CGFloat)] = [(.black.opacity(0.06), 1, 1), (.black.opacity(0.08), 12, 6)]
        static let keycapPressed: [(Color, CGFloat, CGFloat)] = [(.black.opacity(0.06), 1, 0), (.black.opacity(0.05), 6, 3)]
    }

    enum Motion {
        static var keyPress: Animation { .timingCurve(0.25, 0.10, 0.25, 1.0, duration: 0.10) }
        static var keyPressReduced: Animation { .easeOut(duration: 0.08) }
        static var panel: Animation { .spring(response: 0.30, dampingFraction: 1.0) }
        static var banner: Animation { .spring(response: 0.40, dampingFraction: 1.0) }
        static var step: Animation { .spring(response: 0.35, dampingFraction: 1.0) }
        static var hover: Animation { .easeOut(duration: 0.20) }
        static var progress: Animation { .easeInOut(duration: 0.60) }
        static var reducedFade: Animation { .easeInOut(duration: 0.20) }
    }
}

extension View {
    /// Applies a DS two-layer shadow (color, radius, y).
    func dsShadow(_ layers: [(Color, CGFloat, CGFloat)]) -> some View {
        let a = layers.first ?? (.clear, 0, 0)
        let b = layers.count > 1 ? layers[1] : (.clear, 0, 0)
        return self
            .shadow(color: a.0, radius: a.1, x: 0, y: a.2)
            .shadow(color: b.0, radius: b.1, x: 0, y: b.2)
    }
}
