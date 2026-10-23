import AppKit

/// Detects single-color icons, such as GitHub's black mark, that would disappear against a
/// sidebar of the same lightness. Those icons are drawn in the theme's foreground color instead.
public enum FaviconTone: Equatable, Sendable {
    case dark
    case light

    private static let cache = NSMapTable<NSImage, NSNumber>.weakToStrongObjects()
    private static let sampleSide = 16

    /// The icon's tone when every opaque pixel is a dark (or light) neutral; `nil` for icons with
    /// color or contrast of their own.
    public static func monochromeTone(of image: NSImage) -> FaviconTone? {
        if let cached = cache.object(forKey: image) { return decode(cached.intValue) }
        let tone = analyze(image)
        cache.setObject(NSNumber(value: encode(tone)), forKey: image)
        return tone
    }

    private static func analyze(_ image: NSImage) -> FaviconTone? {
        let side = sampleSide
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: side,
                  height: side,
                  bitsPerComponent: 8,
                  bytesPerRow: side * 4,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
              )
        else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: side * side * 4)

        var opaque = 0, dark = 0, light = 0
        for index in 0 ..< side * side {
            let alpha = Double(pixels[index * 4 + 3]) / 255
            guard alpha > 0.5 else { continue }
            opaque += 1
            let channels = (0 ..< 3).map { Double(pixels[index * 4 + $0]) / 255 / alpha }
            let maximum = channels.max() ?? 0, minimum = channels.min() ?? 0
            guard maximum - minimum < 0.12 else { return nil }
            if maximum < 0.3 { dark += 1 } else if minimum > 0.8 { light += 1 }
        }
        // Mostly transparent images carry too little signal; mixed lightness means the icon has
        // its own contrast (a light glyph on a dark tile, for example).
        guard opaque >= side * side / 12 else { return nil }
        if Double(dark) >= Double(opaque) * 0.95 { return .dark }
        if Double(light) >= Double(opaque) * 0.95 { return .light }
        return nil
    }

    private static func encode(_ tone: FaviconTone?) -> Int {
        switch tone {
        case .dark: 1
        case .light: 2
        case nil: 0
        }
    }

    private static func decode(_ value: Int) -> FaviconTone? {
        switch value {
        case 1: .dark
        case 2: .light
        default: nil
        }
    }
}
