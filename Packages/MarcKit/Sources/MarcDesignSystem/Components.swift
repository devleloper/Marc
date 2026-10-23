import AppKit
import SwiftUI

// MARK: - Row background

public struct RowBackground: ViewModifier {
    @Environment(\.themePalette) private var palette
    let isSelected: Bool
    let isHovered: Bool
    let cornerRadius: CGFloat

    public func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(isSelected ? palette.selectedFill : isHovered ? palette.hoverFill : .clear)
                .shadow(color: isSelected && !palette.isDark ? .black.opacity(0.06) : .clear, radius: 1, y: 0.5)
        }
    }
}

public extension View {
    func rowBackground(isSelected: Bool, isHovered: Bool, cornerRadius: CGFloat = Metrics.Sidebar.rowCornerRadius) -> some View {
        modifier(RowBackground(isSelected: isSelected, isHovered: isHovered, cornerRadius: cornerRadius))
    }

    /// A floating panel: translucent material, continuous corners, hairline border and shadow.
    func floatingSurface(
        cornerRadius: CGFloat = Metrics.Popover.cornerRadius,
        material: NSVisualEffectView.Material = .hudWindow,
    ) -> some View {
        modifier(FloatingSurface(cornerRadius: cornerRadius, material: material))
    }
}

struct FloatingSurface: ViewModifier {
    @Environment(\.themePalette) private var palette
    let cornerRadius: CGFloat
    let material: NSVisualEffectView.Material

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background { VisualEffectBackground(material: material, blendingMode: .withinWindow).clipShape(shape) }
            .overlay(shape.strokeBorder(.white.opacity(palette.isDark ? 0.1 : 0.4), lineWidth: 0.5))
            .clipShape(shape)
            .shadow(color: .black.opacity(0.28), radius: 24, y: 10)
    }
}

// MARK: - Buttons

/// A 32×32 toolbar button with a hover fill, used in the sidebar toolbar and panels.
public struct IconButton: View {
    @Environment(\.themePalette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    let systemName: String
    let label: LocalizedStringKey
    let size: CGFloat
    let symbolSize: CGFloat
    let action: () -> Void

    public init(
        _ systemName: String,
        label: LocalizedStringKey,
        size: CGFloat = Metrics.Sidebar.toolbarButtonSize,
        symbolSize: CGFloat = 15,
        action: @escaping () -> Void,
    ) {
        self.systemName = systemName
        self.label = label
        self.size = size
        self.symbolSize = symbolSize
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: symbolSize, weight: .medium))
                .foregroundStyle(isEnabled ? palette.icon : palette.tertiaryText)
                .frame(width: size, height: size)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isHovered && isEnabled ? palette.hoverFill : .clear)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(Motion.hover) { isHovered = hovering } }
        .accessibilityLabel(Text(label))
        .help(Text(label))
    }
}

/// A rounded pill used for prominent sidebar actions such as the update notice.
public struct PillButton: View {
    @Environment(\.themePalette) private var palette
    @State private var isHovered = false
    let title: LocalizedStringKey
    let action: () -> Void

    public init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(palette.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background(Capsule().fill(isHovered ? palette.selectedFill : palette.fieldFill))
                .overlay(Capsule().strokeBorder(palette.separator, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// A full-width accent button for forms and onboarding.
public struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.5))
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(red: 0.2, green: 0.22, blue: 0.75).opacity(configuration.isPressed ? 0.8 : isEnabled ? 1 : 0.45)),
            )
    }
}

// MARK: - Content card

/// The rounded surface that hosts web content, notes and native pages.
public struct ContentCard<Content: View>: View {
    @Environment(\.themePalette) private var palette
    let isFocused: Bool
    let content: Content

    public init(isFocused: Bool = false, @ViewBuilder content: () -> Content) {
        self.isFocused = isFocused
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.Content.cornerRadius, style: .continuous)
        content
            .clipShape(shape)
            .overlay(shape.strokeBorder(
                isFocused ? palette.accent.opacity(0.55) : .black.opacity(palette.isDark ? 0.35 : 0.08),
                lineWidth: isFocused ? 1.5 : 0.5,
            ))
            .shadow(color: .black.opacity(palette.isDark ? 0.3 : 0.12), radius: 3, y: 1)
    }
}

// MARK: - Favicon

public struct FaviconView: View {
    @Environment(\.themePalette) private var palette
    let image: NSImage?
    let fallbackTitle: String
    let size: CGFloat
    let isLoading: Bool

    public init(image: NSImage?, fallbackTitle: String, size: CGFloat = Metrics.Sidebar.iconSize, isLoading: Bool = false) {
        self.image = image
        self.fallbackTitle = fallbackTitle
        self.size = size
        self.isLoading = isLoading
    }

    public var body: some View {
        ZStack {
            if isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(size / 16)
                    .tint(palette.icon)
            } else if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                    .transition(.opacity.animation(Motion.fadeIn))
            } else {
                RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                    .fill(Self.fallbackColor(for: fallbackTitle))
                    .overlay {
                        Text(fallbackTitle.first.map { String($0).uppercased() } ?? "•")
                            .font(.system(size: size * 0.62, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    static func fallbackColor(for title: String) -> Color {
        let hues: [Double] = [0.58, 0.72, 0.85, 0.02, 0.08, 0.14, 0.33, 0.47]
        let hash = title.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Color(hue: hues[hash % hues.count], saturation: 0.55, brightness: 0.75)
    }
}

// MARK: - Misc

public struct ShortcutLabel: View {
    @Environment(\.themePalette) private var palette
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(palette.tertiaryText)
            .monospacedDigit()
    }
}

/// Bridges `NSVisualEffectView` for materials SwiftUI does not expose.
public struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    public init(material: NSVisualEffectView.Material, blendingMode: NSVisualEffectView.BlendingMode = .behindWindow) {
        self.material = material
        self.blendingMode = blendingMode
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        return view
    }

    public func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
    }
}

/// A transient confirmation shown at the bottom of the window.
public struct ToastView: View {
    let message: String
    let symbol: String?
    let actionTitle: String?
    let action: (() -> Void)?

    public init(message: String, symbol: String? = nil, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.message = message
        self.symbol = symbol
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack(spacing: 10) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
            }
            Text(message).font(.system(size: 13, weight: .medium))
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.55, green: 0.6, blue: 1))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(Capsule().fill(Color(white: 0.12).opacity(0.94)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
        .accessibilityElement(children: .combine)
    }
}

/// A thin determinate progress ring, used for downloads in the sidebar footer.
public struct ProgressRing: View {
    let fraction: Double?
    let lineWidth: CGFloat

    public init(fraction: Double?, lineWidth: CGFloat = 2) {
        self.fraction = fraction
        self.lineWidth = lineWidth
    }

    public var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.18), lineWidth: lineWidth)
            if let fraction {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.2), value: fraction)
            } else {
                ProgressView().controlSize(.mini)
            }
        }
    }
}
