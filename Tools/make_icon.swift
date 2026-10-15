// Clack app icon generator. Original artwork drawn in code; not part of the app target.
// Usage: swift Tools/make_icon.swift Clack/Resources/Assets.xcassets/AppIcon.appiconset
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let canvas = 1024

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

func roundedPath(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// Fills `path` with a vertical gradient (top color to bottom color) in a flipped context.
func fillVertical(_ ctx: CGContext, _ path: CGPath, top: UInt32, bottom: UInt32) {
    let rect = path.boundingBox
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let gradient = CGGradient(colorsSpace: space, colors: [rgb(top), rgb(bottom)] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.minY),
                           end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
    ctx.restoreGState()
}

/// Strokes just inside `path` (clip to the shape, stroke at double width).
func innerStroke(_ ctx: CGContext, _ path: CGPath, width: CGFloat, color: CGColor) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.addPath(path)
    ctx.setStrokeColor(color)
    ctx.setLineWidth(width * 2)
    ctx.strokePath()
    ctx.restoreGState()
}

func drawArtwork() -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Flip to a top-left origin so the numbers below read like a design file.
    ctx.translateBy(x: 0, y: CGFloat(canvas))
    ctx.scaleBy(x: 1, y: -1)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // Body with drop shadow. In a flipped CTM a positive y offset in user space moves
    // down on screen only if we account for the flip: shadow offsets are in base space
    // (unflipped), so "down" is negative y there.
    let body = roundedPath(CGRect(x: 100, y: 100, width: 824, height: 824), 185)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: rgb(0x000000, 0.22))
    ctx.addPath(body)
    ctx.setFillColor(rgb(0xE2E3E8))
    ctx.fillPath()
    ctx.restoreGState()
    fillVertical(ctx, body, top: 0xFAFAFB, bottom: 0xE2E3E8)
    innerStroke(ctx, body, width: 2, color: rgb(0x000000, 0.08))

    // Keycap lip (accent underside).
    let lip = roundedPath(CGRect(x: 232, y: 273, width: 560, height: 470), 110)
    ctx.addPath(lip)
    ctx.setFillColor(rgb(0xD63A31))
    ctx.fillPath()

    // Keycap skirt.
    let skirt = roundedPath(CGRect(x: 232, y: 255, width: 560, height: 470), 110)
    ctx.addPath(skirt)
    ctx.setFillColor(rgb(0xC9CBD2))
    ctx.fillPath()
    innerStroke(ctx, skirt, width: 2, color: rgb(0x000000, 0.10))

    // Keycap top face.
    let faceRect = CGRect(x: 292, y: 290, width: 440, height: 340)
    let face = roundedPath(faceRect, 82)
    fillVertical(ctx, face, top: 0xFFFFFF, bottom: 0xEEF0F3)
    innerStroke(ctx, face, width: 2, color: rgb(0x000000, 0.06))
    // Top edge highlight: a 3px line along the top inside the face.
    ctx.saveGState()
    ctx.addPath(face)
    ctx.clip()
    ctx.clip(to: CGRect(x: faceRect.minX, y: faceRect.minY, width: faceRect.width, height: 40))
    let highlight = roundedPath(faceRect.insetBy(dx: 3, dy: 3), 79)
    ctx.addPath(highlight)
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.8))
    ctx.setLineWidth(3)
    ctx.strokePath()
    ctx.restoreGState()

    // Homing bar.
    let bar = roundedPath(CGRect(x: 457, y: 520, width: 110, height: 18), 9)
    ctx.addPath(bar)
    ctx.setFillColor(rgb(0xC3C5CC))
    ctx.fillPath()

    return ctx.makeImage()!
}

func scaled(_ image: CGImage, to size: Int) -> CGImage {
    if size == image.width { return image }
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("Cannot write \(url.path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    if !CGImageDestinationFinalize(dest) { fatalError("Cannot finalize \(url.path)") }
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: swift Tools/make_icon.swift <AppIcon.appiconset directory>")
    exit(1)
}
let outDir = URL(fileURLWithPath: args[1], isDirectory: true)
let master = drawArtwork()
let outputs: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
var cache: [Int: CGImage] = [:]
for (name, size) in outputs {
    let img = cache[size] ?? scaled(master, to: size)
    cache[size] = img
    writePNG(img, to: outDir.appendingPathComponent(name))
    print("wrote \(name) (\(size)px)")
}
