import AppKit
import MarcCore
import MarcDesignSystem
import MarcWebKit
import SwiftUI

/// Picks a Space theme: up to three colors placed on a hue field, appearance and grain.
struct ThemeEditor: View {
    @Binding var theme: Theme
    @State private var selectedHandle = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ForEach(Array(Theme.presets.enumerated()), id: \.offset) { _, preset in
                    Button { theme = preset } label: {
                        ThemeSwatch(theme: preset)
                            .frame(width: 24, height: 24)
                            .overlay(Circle().strokeBorder(.white.opacity(preset == theme ? 0.9 : 0), lineWidth: 2))
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Theme preset")
                }
            }

            ColorField(theme: $theme, selectedHandle: $selectedHandle)
                .frame(height: 150)

            HStack {
                Button {
                    var colors = theme.colors
                    let base = colors.last ?? .white
                    colors.append(base.mixed(with: RGBColor(red: 0.9, green: 0.5, blue: 0.6), amount: 0.5))
                    theme.setColors(colors)
                    selectedHandle = colors.count - 1
                } label: { Label("Add Color", systemImage: "plus.circle") }
                    .disabled(theme.colors.count >= Theme.maximumColorCount)
                Button {
                    var colors = theme.colors
                    colors.removeLast()
                    theme.setColors(colors)
                    selectedHandle = min(selectedHandle, colors.count - 1)
                } label: { Label("Remove", systemImage: "minus.circle") }
                    .disabled(theme.colors.count <= 1)
            }
            .buttonStyle(.pressable)
            .font(.system(size: 12))

            Picker("Appearance", selection: $theme.appearance) {
                Text("Auto").tag(Theme.Appearance.automatic)
                Text("Light").tag(Theme.Appearance.light)
                Text("Dark").tag(Theme.Appearance.dark)
            }
            .pickerStyle(.segmented)

            HStack {
                Image(systemName: "circle.dotted").foregroundStyle(.secondary)
                Slider(value: $theme.grain, in: 0 ... 1) { Text("Grain") }
                    .labelsHidden()
                Image(systemName: "circle.grid.cross").foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Grain")
        }
        .padding(16)
        .frame(width: 300)
    }
}

/// A hue (horizontal) by tone (vertical) field with a draggable handle per theme color.
private struct ColorField: View {
    @Binding var theme: Theme
    @Binding var selectedHandle: Int

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: stride(from: 0.0, through: 1.0, by: 1.0 / 8).map { Color(hue: $0, saturation: 0.55, brightness: 0.9) },
                    startPoint: .leading,
                    endPoint: .trailing,
                )
                LinearGradient(colors: [.white.opacity(0.55), .clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                ForEach(Array(theme.colors.enumerated()), id: \.offset) { index, color in
                    let point = Self.position(of: color, in: proxy.size)
                    Circle()
                        .fill(Color(.sRGB, red: color.red, green: color.green, blue: color.blue))
                        .frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(.white, lineWidth: index == selectedHandle ? 3 : 2))
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                        .position(point)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    selectedHandle = index
                                    update(index, at: value.location, size: proxy.size)
                                },
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    update(selectedHandle, at: value.location, size: proxy.size)
                },
            )
        }
    }

    private func update(_ index: Int, at location: CGPoint, size: CGSize) {
        guard theme.colors.indices.contains(index) else { return }
        var colors = theme.colors
        colors[index] = Self.color(at: location, in: size)
        theme.setColors(colors)
    }

    static func color(at point: CGPoint, in size: CGSize) -> RGBColor {
        let hue = min(max(point.x / max(size.width, 1), 0), 1)
        let tone = min(max(point.y / max(size.height, 1), 0), 1)
        let saturation = 0.3 + 0.5 * tone
        let brightness = 0.98 - 0.55 * tone
        let color = NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1).usingColorSpace(.sRGB) ?? .gray
        return RGBColor(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent)
    }

    static func position(of color: RGBColor, in size: CGSize) -> CGPoint {
        let nsColor = NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1)
        let tone = min(max((0.98 - nsColor.brightnessComponent) / 0.55, 0), 1)
        return CGPoint(x: nsColor.hueComponent * size.width, y: tone * size.height)
    }
}

/// A small gradient preview of a theme as it renders in its appearance.
struct ThemeSwatch: View {
    let theme: Theme

    var body: some View {
        let palette = ThemePalette(
            themeColors: theme.colors.map { PaletteColor(red: $0.red, green: $0.green, blue: $0.blue) },
            isDark: theme.prefersDarkChrome(systemIsDark: NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua),
        )
        Capsule()
            .fill(LinearGradient(
                colors: theme.colors.map { Color(.sRGB, red: $0.red, green: $0.green, blue: $0.blue) },
                startPoint: .leading,
                endPoint: .trailing,
            ))
            .overlay(Capsule().strokeBorder(palette.isDark ? .black.opacity(0.4) : .white.opacity(0.6), lineWidth: 1))
    }
}
