import AppKit
import CoreGraphics
import Foundation

// Renders the background of Marc's disk image window at 1× and 2×:
//
//   swift design/render-dmg-background.swift <output folder>
//
// The window is 660 × 420 pt with 128 pt icons: Marc at (180, 190) and Applications at (480, 190),
// matching packaging/dmg/settings.py. "standard" is used for signed releases; "preview" adds a line
// explaining how to open an ad hoc-signed build. scripts/make-dmg.sh renders it and combines 1× and
// 2× into a TIFF.

let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "packaging/dmg")
let width: CGFloat = 660, height: CGFloat = 420
let appCenter = CGPoint(x: 180, y: 190), applicationsCenter = CGPoint(x: 480, y: 190)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha,
    )
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
}

func glow(_ ctx: CGContext, at center: CGPoint, radius: CGFloat, _ tint: UInt32, _ alpha: CGFloat) {
    ctx.drawRadialGradient(
        gradient([color(tint, alpha), color(tint, 0)]),
        startCenter: center,
        startRadius: 0,
        endCenter: center,
        endRadius: radius,
        options: [],
    )
}

func text(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, centerY: CGFloat) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: style,
    ]
    let line = NSAttributedString(string: string, attributes: attributes)
    let lineHeight = line.size().height
    line.draw(in: CGRect(x: 20, y: centerY - lineHeight / 2, width: width - 40, height: lineHeight))
}

func render(preview: Bool, scale: CGFloat) -> Data {
    let ctx = CGContext(
        data: nil, width: Int(width * scale), height: Int(height * scale), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
    )!
    ctx.translateBy(x: 0, y: height * scale)
    ctx.scaleBy(x: scale, y: -scale) // points, top-left origin

    // White to a breath of lavender, with the icon's violet and teal glowing in the corners.
    ctx.drawLinearGradient(gradient([color(0xFFFFFF), color(0xF3EFFF)]), start: .zero, end: CGPoint(x: 0, y: height), options: [])
    glow(ctx, at: CGPoint(x: 40, y: 10), radius: 300, 0xA58BFF, 0.26)
    glow(ctx, at: CGPoint(x: 640, y: 420), radius: 320, 0x4BE3CD, 0.24)
    glow(ctx, at: CGPoint(x: 330, y: 210), radius: 200, 0x9BD8FF, 0.12)

    // A gently rising arrow from Marc to Applications, violet to teal.
    let start = CGPoint(x: appCenter.x + 92, y: appCenter.y), end = CGPoint(x: applicationsCenter.x - 96, y: applicationsCenter.y)
    let shaft = CGMutablePath()
    shaft.move(to: start)
    shaft.addQuadCurve(to: end, control: CGPoint(x: (start.x + end.x) / 2, y: start.y - 26))
    let head = CGMutablePath()
    head.move(to: CGPoint(x: end.x - 13, y: end.y - 11))
    head.addLine(to: end)
    head.addLine(to: CGPoint(x: end.x - 15, y: end.y + 8))
    let arrow = shaft.copy(strokingWithWidth: 5, lineCap: .round, lineJoin: .round, miterLimit: 4)
        .union(head.copy(strokingWithWidth: 5, lineCap: .round, lineJoin: .round, miterLimit: 4))
    ctx.saveGState()
    ctx.addPath(arrow)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([color(0x8E72FF), color(0x5AA6F6), color(0x2CC9C2)]),
        start: start,
        end: end,
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation],
    )
    ctx.restoreGState()

    // Text, drawn through AppKit so it uses the system font.
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    text(
        "Drag Marc to Applications to install it",
        size: 14,
        weight: .medium,
        color: NSColor(srgbRed: 0.24, green: 0.22, blue: 0.36, alpha: 1),
        centerY: preview ? 334 : 346,
    )
    if preview {
        text(
            "Preview build — on first launch, choose Open Anyway in System Settings › Privacy & Security.",
            size: 11,
            weight: .regular,
            color: NSColor(srgbRed: 0.42, green: 0.40, blue: 0.54, alpha: 1),
            centerY: 362,
        )
    }
    NSGraphicsContext.restoreGraphicsState()

    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
for variant in ["standard", "preview"] {
    for scale in [1, 2] as [CGFloat] {
        let name = scale == 1 ? "background-\(variant).png" : "background-\(variant)@2x.png"
        try render(preview: variant == "preview", scale: scale).write(to: outDir.appending(path: name))
    }
}

print("Rendered DMG backgrounds into \(outDir.path)")
