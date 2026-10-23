import AppKit
import SwiftUI

/// The Space theme painted behind the browser chrome: a diagonal gradient, soft glows taken
/// from the theme's colors, and optional film grain.
public struct ThemeBackground: View {
    let palette: ThemePalette
    let grain: Double

    public init(palette: ThemePalette, grain: Double) {
        self.palette = palette
        self.grain = grain
    }

    public var body: some View {
        ZStack {
            palette.backgroundGradient
            GeometryReader { proxy in
                let glow = palette.backgroundColors.last ?? .black
                RadialGradient(
                    colors: [glow.mixed(with: palette.isDark ? .white : .black, amount: 0.08).color.opacity(0.9), .clear],
                    center: UnitPoint(x: 0.85, y: 0.9),
                    startRadius: 0,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.6,
                )
            }
            if grain > 0 {
                GrainOverlay(opacity: grain * (palette.isDark ? 0.18 : 0.12))
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Tiled monochrome noise.
public struct GrainOverlay: View {
    let opacity: Double

    public init(opacity: Double) {
        self.opacity = opacity
    }

    public var body: some View {
        Image(nsImage: GrainTexture.shared)
            .resizable(resizingMode: .tile)
            .blendMode(.overlay)
            .opacity(opacity)
            .allowsHitTesting(false)
    }
}

enum GrainTexture {
    /// A 128×128 noise tile generated once. A fixed seed keeps the pattern stable across
    /// launches so the grain does not "boil" between windows.
    static let shared: NSImage = {
        let size = 128
        var generator = SplitMix64(seed: 0x4D61_7263)
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 1,
            hasAlpha: false,
            isPlanar: false,
            colorSpaceName: .deviceWhite,
            bytesPerRow: size,
            bitsPerPixel: 8,
        )!
        let pixels = bitmap.bitmapData!
        for index in 0 ..< size * size {
            pixels[index] = UInt8(truncatingIfNeeded: generator.next() >> 56)
        }
        let image = NSImage(size: NSSize(width: size / 2, height: size / 2))
        image.addRepresentation(bitmap)
        return image
    }()
}

/// Small deterministic generator for the grain texture.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
