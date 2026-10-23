import AppKit
import CoreGraphics
import Foundation

// Renders Marc's app icons from vector paths into the asset catalog:
//
//   swift design/render-icons.swift Marc/Resources/Assets.xcassets
//
// The mark is a lowercase "m" made of two arches that share the middle stem; where they overlap,
// the stem glows a lighter blue. Two tiles use it:
// - Marc (white tile): the app icon (AppIcon.appiconset) and the "AppIconMarc" image.
// - Aurora (deep indigo tile): the alternate icon offered in Settings ("AppIconAurora").
// Each size is drawn natively at its pixel size rather than scaled down, so small sizes stay crisp.

let catalog = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Marc/Resources/Assets.xcassets")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha,
    )
}

/// A superellipse (n = 5), close to Apple's continuous-corner icon shape.
func squircle(_ rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2, n: CGFloat = 5
    for step in 0 ... 720 {
        let t = CGFloat(step) / 720 * 2 * .pi
        let c = cos(t), s = sin(t)
        let point = CGPoint(
            x: rect.midX + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n),
            y: rect.midY + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n),
        )
        step == 0 ? path.move(to: point) : path.addLine(to: point)
    }
    path.closeSubpath()
    return path
}

/// An upside-down U, as a centerline for stroking (y grows downward).
func arch(left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat) -> CGPath {
    let r = (right - left) / 2, cx = left + r, cy = top + r
    let path = CGMutablePath()
    path.move(to: CGPoint(x: left, y: bottom))
    path.addLine(to: CGPoint(x: left, y: cy))
    for step in 0 ... 180 {
        let angle = CGFloat.pi + CGFloat(step) / 180 * .pi
        path.addLine(to: CGPoint(x: cx + r * cos(angle), y: cy + r * sin(angle)))
    }
    path.addLine(to: CGPoint(x: right, y: bottom))
    return path
}

func stroked(_ path: CGPath, width: CGFloat) -> CGPath {
    path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
}

let leftArch = stroked(arch(left: 292, right: 512, top: 318, bottom: 742), width: 124)
let rightArch = stroked(arch(left: 512, right: 732, top: 318, bottom: 742), width: 124)
let overlap = leftArch.intersection(rightArch)
let monogram = leftArch.union(rightArch)

func fill(
    _ ctx: CGContext, _ shape: CGPath, _ colors: [CGColor], from: CGPoint, to: CGPoint,
    alpha: CGFloat = 1, blend: CGBlendMode = .normal,
) {
    ctx.saveGState()
    ctx.setAlpha(alpha)
    ctx.setBlendMode(blend)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.addPath(shape)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

struct Style {
    let tile: [CGColor]
    let shadow: (color: CGColor, blur: CGFloat, offset: CGFloat)
    let glowsOnTile: Bool
    let overlap: [CGColor]
    let sheen: CGFloat
}

/// The lighter "aurora" stem where the arches overlap. On the dark tile it is the screen blend of
/// the two arches; on the white tile it is a deeper sky blue so it still stands out.
let marc = Style(
    tile: [color(0xFFFFFF), color(0xF2EEFF)],
    shadow: (color(0x5E44E8, 0.28), 30, -12),
    glowsOnTile: false,
    overlap: [color(0x9BD8FF), color(0x5AA6F6)],
    sheen: 0.24,
)
let aurora = Style(
    tile: [color(0x2B2356), color(0x110D24)],
    shadow: (color(0x7C6BFF, 0.55), 70, 0),
    glowsOnTile: true,
    overlap: [color(0xBFF2FF), color(0x7AC7FC)],
    sheen: 0.18,
)

func render(_ style: Style, pixels: Int) -> Data {
    let scale = CGFloat(pixels) / 1024
    let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
    )!
    ctx.interpolationQuality = .high
    ctx.translateBy(x: 0, y: CGFloat(pixels))
    ctx.scaleBy(x: scale, y: -scale) // 1024-point canvas, top-left origin

    // Tile with the standard macOS drop shadow. Shadow sizes are in device pixels, so scale them.
    let tile = squircle(CGRect(x: 100, y: 100, width: 824, height: 824))
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12 * scale), blur: 28 * scale, color: color(0x000000, 0.28))
    ctx.addPath(tile)
    ctx.setFillColor(style.tile[1])
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tile)
    ctx.clip()
    fill(ctx, tile, style.tile, from: CGPoint(x: 512, y: 100), to: CGPoint(x: 512, y: 924))
    let light = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [color(0xFFFFFF, 0.22), color(0xFFFFFF, 0)] as CFArray, locations: nil,
    )!
    ctx.drawRadialGradient(
        light,
        startCenter: CGPoint(x: 330, y: 230),
        startRadius: 0,
        endCenter: CGPoint(x: 330, y: 230),
        endRadius: 620,
        options: [],
    )

    // Tinted shadow (or glow) under the letter.
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: style.shadow.offset * scale),
        blur: style.shadow.blur * scale,
        color: style.shadow.color,
    )
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.addPath(monogram)
    ctx.setFillColor(color(0xFFFFFF, style.glowsOnTile ? 0.01 : 1))
    ctx.fillPath()
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    fill(ctx, leftArch, [color(0xA58BFF), color(0x6A4CF0)], from: CGPoint(x: 260, y: 300), to: CGPoint(x: 560, y: 780))
    fill(ctx, rightArch, [color(0x4BE3CD), color(0x1BB0D0)], from: CGPoint(x: 480, y: 300), to: CGPoint(x: 780, y: 780))
    fill(ctx, overlap, style.overlap, from: CGPoint(x: 512, y: 318), to: CGPoint(x: 512, y: 804))
    fill(ctx, monogram, [color(0xFFFFFF, style.sheen), color(0xFFFFFF, 0)], from: CGPoint(x: 512, y: 300), to: CGPoint(x: 512, y: 560))
    ctx.restoreGState()

    ctx.addPath(tile)
    ctx.setStrokeColor(color(0x000000, 0.08))
    ctx.setLineWidth(2)
    ctx.strokePath()

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

func write(_ data: Data, _ url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

func json(_ object: Any) -> Data {
    try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
}

// App icon: every size macOS asks for.
let appIcon = catalog.appending(path: "AppIcon.appiconset")
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let name = factor == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try write(render(marc, pixels: points * factor), appIcon.appending(path: name))
        images.append(["filename": name, "idiom": "mac", "scale": "\(factor)x", "size": "\(points)x\(points)"])
    }
}

try write(json(["images": images, "info": ["author": "xcode", "version": 1]]), appIcon.appending(path: "Contents.json"))

// Images for the icon choice in Settings and for switching the Dock icon at run time.
for (name, style) in [("AppIconMarc", marc), ("AppIconAurora", aurora)] {
    let set = catalog.appending(path: "\(name).imageset")
    try write(render(style, pixels: 512), set.appending(path: "\(name).png"))
    try write(render(style, pixels: 1024), set.appending(path: "\(name)@2x.png"))
    try write(json([
        "images": [
            ["filename": "\(name).png", "idiom": "universal", "scale": "1x"],
            ["filename": "\(name)@2x.png", "idiom": "universal", "scale": "2x"],
        ],
        "info": ["author": "xcode", "version": 1],
    ]), set.appending(path: "Contents.json"))
}

print("Rendered app icons into \(catalog.path)")
