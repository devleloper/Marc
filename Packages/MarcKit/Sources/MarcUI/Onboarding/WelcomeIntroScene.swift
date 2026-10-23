import MarcDesignSystem
import SwiftUI

/// One frame of the welcome intro, drawn entirely from `timeline`, so the same moment always looks
/// the same (on screen and in exported frames). The buttons call back to the model.
struct WelcomeIntroScene: View {
    let timeline: WelcomeIntroTimeline
    /// 0 while playing; rises to 1 as the intro zooms away after "Get Started".
    var exit: Double = 0
    var isMuted = false
    var onGetStarted: () -> Void = {}
    var onToggleMute: () -> Void = {}

    static let subtitle = "A calmer, more personal home for the web."

    struct SpaceCard {
        let symbol: String
        let name: String
        let color: UInt32
    }

    static let cards = [
        SpaceCard(symbol: "briefcase.fill", name: "Work", color: 0x8E72FF),
        SpaceCard(symbol: "book.fill", name: "Research", color: 0x5AA6F6),
        SpaceCard(symbol: "music.note", name: "Music", color: 0xF06BC4),
        SpaceCard(symbol: "house.fill", name: "Personal", color: 0x2CC9C2),
        SpaceCard(symbol: "airplane", name: "Travel", color: 0xFF9F6B),
        SpaceCard(symbol: "sparkles", name: "Ideas", color: 0xF5C95C),
    ]

    /// Where the mark is drawn: centered while it draws, then smaller above the greeting.
    static func markFrame(in size: CGSize, timeline: WelcomeIntroTimeline) -> CGRect {
        let width = size.height * 0.34 * timeline.markScale
        let height = width * WelcomeMarkGeometry.aspectRatio
        let center = CGPoint(x: size.width / 2, y: size.height * timeline.markCenterY)
        return CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                WelcomeBackdrop(timeline: timeline)
                spaceCards(in: size)
                WelcomeBurst(timeline: timeline)
                greeting(in: size)
            }
            .scaleEffect(1 + 0.12 * exit)
            .blur(radius: 24 * exit)
            .opacity(1 - exit)
            .overlay(alignment: .topTrailing) { controls }
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("welcomeIntro")
    }

    // MARK: Greeting

    private func greeting(in size: CGSize) -> some View {
        let fontSize = size.height * 0.072
        let letters = (0 ..< WelcomeTitleRenderer.glyphCount).map(timeline.titleLetter)
        return ZStack {
            Text("Welcome to \(Text("Marc").foregroundStyle(WelcomeTitleRenderer.brandGradient))")
                .font(.system(size: fontSize, weight: .bold))
                .foregroundStyle(.white)
                .textRenderer(WelcomeTitleRenderer(letters: letters, sheen: timeline.titleSheen, rise: fontSize * 0.45))
                .shadow(color: Color(hex: 0x8E72FF, opacity: 0.5 * (letters.last ?? 0)), radius: fontSize * 0.45)
                .fixedSize()
                .position(x: size.width / 2, y: size.height * 0.505)
                .accessibilityLabel("Welcome to Marc")
            Text(Self.subtitle)
                .font(.system(size: fontSize * 0.3, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .opacity(timeline.subtitle)
                .offset(y: (1 - timeline.subtitle) * fontSize * 0.25)
                .blur(radius: (1 - timeline.subtitle) * 6)
                .fixedSize()
                .position(x: size.width / 2, y: size.height * 0.588)
            getStarted(fontSize: fontSize)
                .position(x: size.width / 2, y: size.height * 0.7)
            Text("Press Return to begin")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .opacity(timeline.hint)
                .fixedSize()
                .position(x: size.width / 2, y: size.height - 44)
        }
        .frame(width: size.width, height: size.height)
    }

    private func getStarted(fontSize: CGFloat) -> some View {
        let gradient = LinearGradient(colors: WelcomeTitleRenderer.brandColors, startPoint: .leading, endPoint: .trailing)
        let pulse = timeline.buttonPulse
        return Button(action: onGetStarted) {
            Text("Get Started")
                .font(.system(size: fontSize * 0.27, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, fontSize * 0.62)
                .padding(.vertical, fontSize * 0.22)
                .background {
                    Capsule()
                        .fill(gradient)
                        .blur(radius: fontSize * 0.32)
                        .opacity(0.5 + 0.25 * pulse)
                        .scaleEffect(1.06 + 0.04 * pulse)
                }
                .background(Capsule().fill(gradient))
                .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .keyboardShortcut(.defaultAction)
        .scaleEffect(0.5 + 0.5 * timeline.button)
        .opacity(min(max(timeline.button, 0), 1))
        .allowsHitTesting(timeline.button > 0.5)
        .accessibilityIdentifier("welcomeGetStarted")
    }

    // MARK: Space cards

    /// Glass cards for a few example Spaces, flying out from the greeting onto a slow orbit.
    private func spaceCards(in size: CGSize) -> some View {
        let center = CGPoint(x: size.width / 2, y: size.height * 0.52)
        let radiusX = min(size.width * 0.41, size.height * 0.78)
        let radiusY = size.height * 0.31
        let unit = size.height / 900
        return ZStack {
            ForEach(Self.cards.indices, id: \.self) { index in
                let appearance = timeline.cardAppearance(index)
                let angle = timeline.cardAngle(index)
                // 0 at the back of the orbit (top), 1 at the front (bottom).
                let depth = (sin(angle) + 1) / 2
                let orbit = CGPoint(
                    x: center.x + radiusX * cos(angle),
                    y: center.y + radiusY * sin(angle) + timeline.cardFloat(index) * size.height * 0.008,
                )
                WelcomeSpaceCardView(card: Self.cards[index], unit: unit)
                    .scaleEffect((0.78 + 0.3 * depth) * (0.3 + 0.7 * appearance))
                    .rotation3DEffect(.degrees(-cos(angle) * 16), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                    .blur(radius: (1 - depth) * 2.5 + (1 - appearance) * 8)
                    .opacity(appearance * (0.5 + 0.45 * depth))
                    .position(
                        x: center.x + (orbit.x - center.x) * appearance,
                        y: center.y + (orbit.y - center.y) * appearance,
                    )
                    .zIndex(depth)
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 10) {
            Button(action: onToggleMute) {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(.white.opacity(0.1)))
                    .contentShape(Circle())
            }
            .keyboardShortcut("m", modifiers: [])
            .help(isMuted ? "Unmute (M)" : "Mute (M)")
            .accessibilityLabel(isMuted ? "Unmute" : "Mute")
            .accessibilityIdentifier("welcomeMute")
            Button(action: onGetStarted) {
                Text("Skip")
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .background(Capsule().fill(.white.opacity(0.1)))
                    .contentShape(Capsule())
            }
            .keyboardShortcut(.cancelAction)
            .help("Skip the intro (Esc)")
            .accessibilityIdentifier("welcomeSkip")
        }
        .buttonStyle(.pressable)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white.opacity(0.82))
        .padding(.top, 28)
        .padding(.trailing, 32)
        .opacity(timeline.controls * (1 - exit))
    }
}

/// A miniature Space: its icon, name and a few tab rows.
private struct WelcomeSpaceCardView: View {
    let card: WelcomeIntroScene.SpaceCard
    let unit: CGFloat

    var body: some View {
        let tint = Color(hex: card.color)
        let shape = RoundedRectangle(cornerRadius: 18 * unit, style: .continuous)
        VStack(alignment: .leading, spacing: 9 * unit) {
            HStack(spacing: 8 * unit) {
                Image(systemName: card.symbol)
                    .font(.system(size: 11 * unit, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24 * unit, height: 24 * unit)
                    .background(Circle().fill(tint.gradient))
                Text(card.name)
                    .font(.system(size: 13 * unit, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }
            ForEach(0 ..< 3, id: \.self) { row in
                HStack(spacing: 7 * unit) {
                    RoundedRectangle(cornerRadius: 3 * unit, style: .continuous)
                        .fill(.white.opacity(0.32))
                        .frame(width: 10 * unit, height: 10 * unit)
                    Capsule()
                        .fill(.white.opacity(0.16))
                        .frame(width: CGFloat(78 - row * 16) * unit, height: 6 * unit)
                }
            }
        }
        .padding(15 * unit)
        .frame(width: 168 * unit, height: 122 * unit, alignment: .topLeading)
        .background {
            shape
                .fill(LinearGradient(colors: [tint.opacity(0.4), tint.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .background(shape.fill(.white.opacity(0.05)))
        }
        .overlay {
            shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.38), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom),
                lineWidth: 1,
            )
        }
        .shadow(color: tint.opacity(0.35), radius: 24 * unit, y: 10 * unit)
    }
}

/// Reveals the title glyph by glyph (each rises, sharpens and fades in), then sweeps a glow
/// across it. Drawing the laid-out text keeps its kerning, unlike a row of single letters.
struct WelcomeTitleRenderer: TextRenderer {
    static let glyphCount = "Welcome to Marc".count
    static let brandColors = [Color(hex: 0xA58BFF), Color(hex: 0x6FA8FA), Color(hex: 0x4BE3CD)]
    static let brandGradient = LinearGradient(colors: brandColors, startPoint: .leading, endPoint: .trailing)

    /// Appearance of each glyph, 0...1.
    let letters: [Double]
    /// Position of the highlight across the title, as a fraction of its width.
    let sheen: Double
    /// How far a glyph rises while it appears.
    let rise: CGFloat

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let width = max(layout.first?.typographicBounds.width ?? 1, 1)
        var index = 0
        for line in layout {
            for run in line {
                for glyph in run {
                    let appearance = index < letters.count ? letters[index] : 1
                    index += 1
                    guard appearance > 0 else { continue }
                    var copy = context
                    copy.opacity = appearance
                    copy.translateBy(x: 0, y: (1 - appearance) * rise)
                    if appearance < 1 {
                        copy.addFilter(.blur(radius: (1 - appearance) * rise * 0.35))
                    }
                    copy.draw(glyph)
                    let position = glyph.typographicBounds.rect.midX / width
                    let highlight = exp(-pow((position - sheen) / 0.1, 2))
                    if highlight > 0.01 {
                        // A bloom rather than a brighter copy, which white glyphs wouldn't show.
                        var shine = copy
                        shine.blendMode = .plusLighter
                        shine.opacity = appearance * highlight * 0.9
                        shine.addFilter(.blur(radius: rise * 0.22))
                        shine.draw(glyph)
                    }
                }
            }
        }
    }
}
