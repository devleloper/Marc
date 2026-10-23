import AppKit
import CoreGraphics
import Foundation

// Renders the repository's social preview (the image GitHub, LinkedIn and others show for links
// to the repository) in Marc's colors with the app icon:
//
//   swift design/render-social-preview.swift docs/images/social-preview.png
//
// GitHub wants 1280 × 640; important content stays inside a generous margin because some sites
// crop the edges. Upload the result in the repository's Settings › General › Social preview.

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "docs/images/social-preview.png")
let iconURL = URL(fileURLWithPath: "Marc/Resources/Assets.xcassets/AppIconMarc.imageset/AppIconMarc@2x.png")
let width: CGFloat = 1280, height: CGFloat = 640

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

func font(_ size: CGFloat, _ weight: NSFont.Weight, rounded: Bool = false) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    guard rounded, let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
    return NSFont(descriptor: descriptor, size: size) ?? base
}

func draw(_ string: String, _ font: NSFont, _ hex: UInt32, at origin: CGPoint, kern: CGFloat = 0) {
    let rgb = NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1,
    )
    NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: rgb, .kern: kern]).draw(at: origin)
}

let scale: CGFloat = 1
let ctx = CGContext(
    data: nil, width: Int(width * scale), height: Int(height * scale), bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue,
)!
ctx.translateBy(x: 0, y: height * scale)
ctx.scaleBy(x: scale, y: -scale) // top-left origin

// The disk image's palette: white to lavender with the icon's violet and teal glowing at the edges.
ctx.drawLinearGradient(gradient([color(0xFFFFFF), color(0xF1ECFF)]), start: .zero, end: CGPoint(x: 0, y: height), options: [])
glow(ctx, at: CGPoint(x: 120, y: 40), radius: 560, 0xA58BFF, 0.30)
glow(ctx, at: CGPoint(x: 1230, y: 640), radius: 600, 0x4BE3CD, 0.28)
glow(ctx, at: CGPoint(x: 330, y: 330), radius: 300, 0x9BD8FF, 0.16)

// App icon on the left.
if let icon = NSImage(contentsOf: iconURL)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
    ctx.saveGState()
    ctx.translateBy(x: 96, y: 150 + 340)
    ctx.scaleBy(x: 1, y: -1) // images draw bottom-up
    ctx.interpolationQuality = .high
    ctx.draw(icon, in: CGRect(x: 0, y: 0, width: 340, height: 340))
    ctx.restoreGState()
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
draw("Marc", font(150, .bold, rounded: true), 0x1E1838, at: CGPoint(x: 476, y: 150), kern: -2)
draw("A native, open-source browser for macOS", font(38, .semibold), 0x34305A, at: CGPoint(x: 482, y: 340))
draw("Sidebar · Spaces · Command Bar · Split View", font(28, .regular), 0x6B6880, at: CGPoint(x: 482, y: 398))
draw("github.com/devleloper/Marc", font(24, .medium), 0x7C5CFF, at: CGPoint(x: 482, y: 480))
NSGraphicsContext.restoreGraphicsState()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
try rep.representation(using: .png, properties: [:])!.write(to: output)
print("Rendered \(output.path)")
