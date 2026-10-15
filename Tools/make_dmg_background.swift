// Renders Tools/dmg/background.tiff (1x + 2x) for the installer window.
// Icon centres must match icon_locations in dmg_settings.py.  Run: swift Tools/make_dmg_background.swift
import AppKit

let W: CGFloat = 660, H: CGFloat = 420
let appIcon = CGPoint(x: 170, y: 210), appsIcon = CGPoint(x: 490, y: 210)   // from top-left

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    func y(_ top: CGFloat) -> CGFloat { H - top }   // top-left → AppKit coords

    // Apple-style light grey-white ground.
    NSGradient(colors: [NSColor(calibratedWhite: 0.985, alpha: 1), NSColor(calibratedWhite: 0.935, alpha: 1)])!
        .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)

    func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, top: CGFloat, kern: CGFloat = 0) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                    .foregroundColor: color, .kern: kern]
        let str = NSAttributedString(string: s, attributes: attrs)
        let sz = str.size()
        str.draw(at: NSPoint(x: (W - sz.width) / 2, y: y(top) - sz.height))
    }
    text("Clack", size: 30, weight: .semibold, color: NSColor(calibratedWhite: 0.11, alpha: 1), top: 36, kern: -0.6)
    text("Mechanical keyboard sounds for your Mac.", size: 14, weight: .regular,
         color: NSColor(calibratedWhite: 0.43, alpha: 1), top: 76)

    // Arrow between the icons.
    let path = NSBezierPath()
    let startX = appIcon.x + 84, endX = appsIcon.x - 84, ay = y(appIcon.y)
    path.move(to: NSPoint(x: startX, y: ay))
    path.curve(to: NSPoint(x: endX, y: ay), controlPoint1: NSPoint(x: startX + 50, y: ay + 16), controlPoint2: NSPoint(x: endX - 50, y: ay + 16))
    path.lineWidth = 4; path.lineCapStyle = .round
    NSColor(calibratedWhite: 0.55, alpha: 1).setStroke()
    path.setLineDash([1, 10], count: 2, phase: 0)
    path.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: endX - 14, y: ay + 11)); head.line(to: NSPoint(x: endX + 2, y: ay)); head.line(to: NSPoint(x: endX - 14, y: ay - 11))
    head.lineWidth = 4; head.lineCapStyle = .round; head.lineJoinStyle = .round
    head.stroke()

    text("Drag Clack into Applications, then open it", size: 13, weight: .medium,
         color: NSColor(calibratedWhite: 0.25, alpha: 1), top: 324)
    text("Lives in your menu bar. Nothing you type leaves your Mac.", size: 11, weight: .regular,
         color: NSColor(calibratedWhite: 0.50, alpha: 1), top: 348)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let dir = "Tools/dmg"
for (scale, name) in [(1.0, "bg.png"), (2.0, "bg@2x.png")] {
    try! render(scale: scale).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/\(name)"))
}
let t = Process()
t.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
t.arguments = ["-cathidpicheck", "\(dir)/bg.png", "\(dir)/bg@2x.png", "-out", "\(dir)/background.tiff"]
try! t.run(); t.waitUntilExit()
