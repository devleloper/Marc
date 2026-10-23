import SwiftUI
import Testing
@testable import MarcDesignSystem

struct ThemePaletteTests {
    func hex(_ color: PaletteColor) -> String {
        String(
            format: "#%02X%02X%02X",
            Int((color.red * 255).rounded()),
            Int((color.green * 255).rounded()),
            Int((color.blue * 255).rounded()),
        )
    }

    @Test func `dark shading reproduces Arc's measured sidebar color`() {
        // The default mid tone, shaded for a dark appearance, lands next to the #100E1F measured
        // on Arc's sidebar.
        let midTone = PaletteColor(red: 91 / 255, green: 75 / 255, blue: 154 / 255)
        let palette = ThemePalette(themeColors: [midTone], isDark: true)
        #expect(hex(palette.backgroundColors[0]) == "#100E1C")
    }

    @Test func `light tint moves towards white`() {
        let palette = ThemePalette(themeColors: [PaletteColor(red: 0.2, green: 0.4, blue: 0.6)], isDark: false)
        let background = palette.backgroundColors[0]
        #expect(background.red > 0.6)
        #expect(background.blue > 0.8)
    }

    @Test func `empty theme colors fall back to a default`() {
        #expect(ThemePalette(themeColors: [], isDark: true).backgroundColors.count == 1)
    }

    @Test func `mixing clamps the amount`() {
        let black = PaletteColor.black
        #expect(black.mixed(with: .white, amount: 2) == .white)
        #expect(black.mixed(with: .white, amount: -1) == .black)
        #expect(black.mixed(with: .white, amount: 0.5).red == 0.5)
    }

    @Test func `grain noise is deterministic`() {
        var first = SplitMix64(seed: 42)
        var second = SplitMix64(seed: 42)
        #expect((0 ..< 8).map { _ in first.next() } == (0 ..< 8).map { _ in second.next() })
    }
}
