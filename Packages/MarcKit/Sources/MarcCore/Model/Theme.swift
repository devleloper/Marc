import Foundation

/// The visual theme of a Space: a gradient of one to three colors rendered behind the browser
/// chrome, an appearance preference and an optional film-grain intensity.
public struct Theme: Hashable, Sendable, Codable {
    public enum Appearance: String, Hashable, Sendable, Codable, CaseIterable {
        case automatic
        case light
        case dark
    }

    public static let maximumColorCount = 3

    public private(set) var colors: [RGBColor]
    public var appearance: Appearance
    /// Film grain strength in `0...1`.
    public var grain: Double

    public init(colors: [RGBColor], appearance: Appearance = .automatic, grain: Double = 0) {
        precondition(!colors.isEmpty, "A theme needs at least one color")
        self.colors = Array(colors.prefix(Self.maximumColorCount))
        self.appearance = appearance
        self.grain = min(max(grain, 0), 1)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedColors = try container.decode([RGBColor].self, forKey: .colors)
        try self.init(
            colors: decodedColors.isEmpty ? Self.default.colors : decodedColors,
            appearance: container.decodeIfPresent(Appearance.self, forKey: .appearance) ?? .automatic,
            grain: container.decodeIfPresent(Double.self, forKey: .grain) ?? 0,
        )
    }

    public mutating func setColors(_ newColors: [RGBColor]) {
        guard !newColors.isEmpty else { return }
        colors = Array(newColors.prefix(Self.maximumColorCount))
    }

    /// Whether chrome drawn over this theme should use dark-appearance (light) foregrounds.
    public func prefersDarkChrome(systemIsDark: Bool) -> Bool {
        switch appearance {
        case .light: false
        case .dark: true
        case .automatic: systemIsDark
        }
    }

    /// Theme colors are mid tones; renderers derive darker or lighter backgrounds from them
    /// according to the appearance.
    public static let `default` = Theme(
        colors: [RGBColor(hex: "#5B4B9A")!, RGBColor(hex: "#7A4A8C")!],
        appearance: .dark,
        grain: 0.15,
    )

    public static let incognito = Theme(colors: [RGBColor(hex: "#3A3A3C")!], appearance: .dark, grain: 0.25)

    /// Curated starting points for new Spaces.
    public static let presets: [Theme] = [
        .default,
        Theme(colors: [RGBColor(hex: "#F2A27A")!, RGBColor(hex: "#E879A0")!], appearance: .light, grain: 0.1),
        Theme(colors: [RGBColor(hex: "#6CC4B4")!, RGBColor(hex: "#6FA8DC")!], appearance: .light, grain: 0.1),
        Theme(colors: [RGBColor(hex: "#2F7A5F")!, RGBColor(hex: "#3E8E6B")!], appearance: .dark, grain: 0.15),
        Theme(colors: [RGBColor(hex: "#C2683A")!, RGBColor(hex: "#9C3D2A")!], appearance: .dark, grain: 0.2),
        Theme(colors: [RGBColor(hex: "#B9A7F2")!], appearance: .light, grain: 0),
        Theme(
            colors: [RGBColor(hex: "#6B3FA0")!, RGBColor(hex: "#C2457A")!, RGBColor(hex: "#F08A5D")!],
            appearance: .dark,
            grain: 0.2,
        ),
        Theme(colors: [RGBColor(hex: "#F7D774")!, RGBColor(hex: "#F4A261")!], appearance: .light, grain: 0.05),
    ]
}

/// An sRGB color with components in `0...1`.
public struct RGBColor: Hashable, Sendable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
    }

    /// Parses `#RRGGBB` or `RRGGBB`.
    public init?(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespaces)
        if string.hasPrefix("#") { string.removeFirst() }
        guard string.count == 6, let value = UInt32(string, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
        )
    }

    public var hex: String {
        String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    /// WCAG relative luminance.
    public var relativeLuminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.039_28 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    public func mixed(with other: RGBColor, amount: Double) -> RGBColor {
        let t = Self.clamp(amount)
        return RGBColor(
            red: red + (other.red - red) * t,
            green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t,
        )
    }

    public static let white = RGBColor(red: 1, green: 1, blue: 1)
    public static let black = RGBColor(red: 0, green: 0, blue: 0)

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
