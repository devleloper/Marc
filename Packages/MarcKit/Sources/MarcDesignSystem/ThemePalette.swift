import SwiftUI

/// An sRGB color with components in `0...1`, independent of any UI framework.
public nonisolated struct PaletteColor: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let white = PaletteColor(red: 1, green: 1, blue: 1)
    public static let black = PaletteColor(red: 0, green: 0, blue: 0)

    public func mixed(with other: PaletteColor, amount: Double) -> PaletteColor {
        let t = min(max(amount, 0), 1)
        return PaletteColor(
            red: red + (other.red - red) * t,
            green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t,
        )
    }

    public var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue)
    }
}

/// Colors for chrome drawn over a Space theme. Theme colors are mid tones; dark appearances
/// shade them towards black and light appearances tint them towards white, then foregrounds
/// and fills are layered as translucent white or black so that they adapt to any hue.
public nonisolated struct ThemePalette: Hashable, Sendable {
    public static let darkShade = 0.82
    public static let lightTint = 0.62

    public let isDark: Bool
    public let backgroundColors: [PaletteColor]

    public init(themeColors: [PaletteColor], isDark: Bool) {
        self.isDark = isDark
        let base = themeColors.isEmpty ? [PaletteColor(red: 0.36, green: 0.29, blue: 0.6)] : themeColors
        backgroundColors = base.map { color in
            isDark ? color.mixed(with: .black, amount: Self.darkShade) : color.mixed(with: .white, amount: Self.lightTint)
        }
    }

    public static let fallbackDark = ThemePalette(themeColors: [PaletteColor(red: 0.36, green: 0.29, blue: 0.6)], isDark: true)

    private var ink: Color { isDark ? .white : .black }

    public var primaryText: Color { ink.opacity(isDark ? 0.92 : 0.85) }
    public var secondaryText: Color { ink.opacity(isDark ? 0.5 : 0.55) }
    public var tertiaryText: Color { ink.opacity(isDark ? 0.3 : 0.35) }
    public var icon: Color { ink.opacity(isDark ? 0.62 : 0.6) }
    /// Measured on Arc: 10 % white for hover and fields, 20 % for the selected row.
    public var hoverFill: Color { isDark ? .white.opacity(0.1) : .white.opacity(0.35) }
    public var selectedFill: Color { isDark ? .white.opacity(0.2) : .white.opacity(0.7) }
    public var fieldFill: Color { isDark ? .white.opacity(0.1) : .white.opacity(0.4) }
    public var separator: Color { ink.opacity(isDark ? 0.1 : 0.1) }
    public var pressedFill: Color { isDark ? .white.opacity(0.26) : .white.opacity(0.85) }
    public var windowEdgeHighlight: Color { .white.opacity(isDark ? 0.18 : 0.5) }
    public var accent: Color { Color(red: 0.27, green: 0.28, blue: 0.82) }

    public var backgroundGradient: LinearGradient {
        let colors = backgroundColors.count == 1 ? [backgroundColors[0], backgroundColors[0]] : backgroundColors
        return LinearGradient(colors: colors.map(\.color), startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    public var colorScheme: ColorScheme { isDark ? .dark : .light }
}

public extension EnvironmentValues {
    @Entry var themePalette: ThemePalette = .fallbackDark
}
