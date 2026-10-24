import SwiftUI

/// The intro's light backdrop, in the colors of Marc's social preview: lavender, white and mint,
/// with slowly drifting pastel light and soft particles floating outward.
struct WelcomeBackdrop: View {
    let timeline: WelcomeIntroTimeline

    private struct Blob {
        let color: UInt32
        let x: Double
        let y: Double
        let radius: Double
        let speed: Double
        let phase: Double
    }

    private static let blobs = [
        Blob(color: 0xDCD0FF, x: 0.16, y: 0.18, radius: 0.55, speed: 0.11, phase: 0),
        Blob(color: 0xD3E6FF, x: 0.78, y: 0.22, radius: 0.48, speed: 0.09, phase: 1.7),
        Blob(color: 0xC2EEE8, x: 0.82, y: 0.86, radius: 0.6, speed: 0.13, phase: 3.1),
        Blob(color: 0xF2DDF8, x: 0.14, y: 0.88, radius: 0.42, speed: 0.07, phase: 4.4),
    ]

    private struct Particle {
        let x: Double
        let y: Double
        let depth: Double
        let size: Double
        let twinkle: Double
        let color: Color
    }

    private static let particleColors = [Color(hex: 0x9C84FF), Color(hex: 0x6FA8FA), Color(hex: 0x43CFC0), Color(hex: 0xE59BDA)]

    private static let particles = (0 ..< 140).map { index in
        Particle(
            x: welcomeRandom(index, 1) * 2 - 1,
            y: welcomeRandom(index, 2) * 2 - 1,
            depth: welcomeRandom(index, 3),
            size: 0.8 + welcomeRandom(index, 4) * 1.6,
            twinkle: welcomeRandom(index, 5) * 2 * .pi,
            color: particleColors[index % particleColors.count],
        )
    }

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.opacity = timeline.backdrop
            context.fill(
                Path(rect),
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: Color(hex: 0xE6DFFF), location: 0),
                        .init(color: Color(hex: 0xF7F6FD), location: 0.5),
                        .init(color: Color(hex: 0xC8EAEE), location: 1),
                    ]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: size.height),
                ),
            )
            drawLight(in: context, size: size)
            drawParticles(in: context, size: size)
        }
    }

    private func drawLight(in context: GraphicsContext, size: CGSize) {
        let time = timeline.time
        let alpha = 0.7 * timeline.auroraIntensity
        for blob in Self.blobs {
            let center = CGPoint(
                x: size.width * (blob.x + 0.06 * sin(time * blob.speed + blob.phase)),
                y: size.height * (blob.y + 0.05 * cos(time * blob.speed * 1.3 + blob.phase)),
            )
            let radius = max(size.width, size.height) * blob.radius * (0.92 + 0.08 * sin(time * 0.3 + blob.phase))
            let color = Color(hex: blob.color)
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                with: .radialGradient(
                    Gradient(colors: [color.opacity(alpha), color.opacity(alpha * 0.4), color.opacity(0)]),
                    center: center,
                    startRadius: 0,
                    endRadius: radius,
                ),
            )
        }
        // A bright center, as on the preview card.
        let center = CGPoint(x: size.width / 2, y: size.height * 0.45)
        let radius = max(size.width, size.height) * 0.45
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                Gradient(colors: [.white.opacity(0.55 * timeline.auroraIntensity), .white.opacity(0)]),
                center: center,
                startRadius: 0,
                endRadius: radius,
            ),
        )
    }

    private func drawParticles(in context: GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let spread = max(size.width, size.height) * 0.16
        for particle in Self.particles {
            let travelled = particle.depth - timeline.particleTravel
            let depth = travelled - floor(travelled)
            // Near particles are bigger; each fades out before it wraps to the back.
            let distance = 0.08 + 0.92 * depth
            let nearness = 1 - depth
            let twinkle = 0.65 + 0.35 * sin(timeline.time * 1.6 + particle.twinkle)
            let alpha = 0.6 * pow(nearness, 1.2) * twinkle * timeline.particleOpacity
                * smoothstep(0, 0.1, depth) * smoothstep(0, 0.25, nearness)
            guard alpha > 0.01 else { continue }
            let position = CGPoint(x: center.x + particle.x * spread / distance, y: center.y + particle.y * spread / distance)
            let radius = particle.size * (0.6 + 2 * nearness)
            context.fill(
                Path(ellipseIn: CGRect(x: position.x - radius * 3, y: position.y - radius * 3, width: radius * 6, height: radius * 6)),
                with: .radialGradient(
                    Gradient(colors: [particle.color.opacity(alpha * 0.35), particle.color.opacity(0)]),
                    center: position,
                    startRadius: 0,
                    endRadius: radius * 3,
                ),
            )
            context.fill(
                Path(ellipseIn: CGRect(x: position.x - radius, y: position.y - radius, width: radius * 2, height: radius * 2)),
                with: .color(particle.color.opacity(alpha)),
            )
        }
    }
}

/// The mark drawing itself with a soft pen of light, then settling into the white icon tile with a
/// gentle bloom, ripples and drifting sparks.
struct WelcomeBurst: View {
    let timeline: WelcomeIntroTimeline

    private static let sparkColors = [Color(hex: 0x9C84FF), Color(hex: 0x6FA8FA), Color(hex: 0x3FCFC0), Color(hex: 0xEC9BD8)]
    private static let ringColors = [
        Color(hex: 0xA58BFF), Color(hex: 0x7DB8F7), Color(hex: 0x4BE3CD), Color(hex: 0xF0A8E0), Color(hex: 0xA58BFF),
    ]
    /// Lighter tints of each arch, for its pen tip and glitter.
    private static let penColors: [WelcomeMarkGeometry.Side: Color] = [.left: Color(hex: 0xB9A4FF), .right: Color(hex: 0x6FE6D4)]

    var body: some View {
        Canvas { context, size in
            let mark = WelcomeMarkGeometry(frame: WelcomeIntroScene.markFrame(in: size, timeline: timeline))
            drawHalo(in: context, mark: mark)
            // The bloom sits behind the icon, so light opens up around it without washing it out.
            drawFlash(in: context, mark: mark, size: size)
            drawShockwaves(in: context, mark: mark, size: size)
            drawTile(in: context, mark: mark)
            drawMark(in: context, mark: mark)
            drawPen(in: context, mark: mark)
            drawSparks(in: context, mark: mark, size: size)
        }
    }

    private func circle(_ center: CGPoint, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    /// Soft pastel light behind the mark that grows as it draws and blooms at the impact.
    private func drawHalo(in context: GraphicsContext, mark: WelcomeMarkGeometry) {
        let alpha = timeline.markOpacity * (0.5 * timeline.drawingGlow + 0.3 * timeline.impactGlow)
        guard alpha > 0.005 else { return }
        let radius = mark.frame.width * (1.3 + 0.4 * timeline.impactGlow)
        context.fill(
            circle(mark.center, radius),
            with: .radialGradient(
                Gradient(colors: [
                    Color(hex: 0xCDBDFF, opacity: alpha),
                    Color(hex: 0xBDEDE6, opacity: alpha * 0.5),
                    Color(hex: 0xBDEDE6, opacity: 0),
                ]),
                center: mark.center,
                startRadius: 0,
                endRadius: radius,
            ),
        )
    }

    /// The white tile of the app icon, forming behind the mark as it lands.
    private func drawTile(in context: GraphicsContext, mark: WelcomeMarkGeometry) {
        let appearance = timeline.tile
        guard appearance > 0 else { return }
        let tile = mark.tile(appearance: appearance)
        let bounds = tile.boundingRect
        var context = context
        context.opacity = appearance
        context.drawLayer { shadow in
            shadow.addFilter(.blur(radius: bounds.width * 0.06))
            shadow.fill(tile.offsetBy(dx: 0, dy: bounds.width * 0.035), with: .color(Color(hex: 0x3B2E8C, opacity: 0.2)))
        }
        context.fill(
            tile,
            with: .linearGradient(
                Gradient(colors: [.white, Color(hex: 0xF2EEFF)]),
                startPoint: CGPoint(x: bounds.midX, y: bounds.minY),
                endPoint: CGPoint(x: bounds.midX, y: bounds.maxY),
            ),
        )
        context.stroke(tile, with: .color(.black.opacity(0.06)), lineWidth: 1)
    }

    private func drawMark(in context: GraphicsContext, mark: WelcomeMarkGeometry) {
        let left = timeline.leftArchDrawn > 0 ? mark.stroke(of: .left, drawn: timeline.leftArchDrawn) : Path()
        let right = timeline.rightArchDrawn > 0 ? mark.stroke(of: .right, drawn: timeline.rightArchDrawn) : Path()
        let leftShading = GraphicsContext.Shading.linearGradient(
            Gradient(colors: WelcomeMarkGeometry.leftColors),
            startPoint: mark.leftGradient.start,
            endPoint: mark.leftGradient.end,
        )
        let rightShading = GraphicsContext.Shading.linearGradient(
            Gradient(colors: WelcomeMarkGeometry.rightColors),
            startPoint: mark.rightGradient.start,
            endPoint: mark.rightGradient.end,
        )
        let leftOpacity = timeline.markOpacity * timeline.archOpacity(drawn: timeline.leftArchDrawn)
        let rightOpacity = timeline.markOpacity * timeline.archOpacity(drawn: timeline.rightArchDrawn)
        // A colored glow that follows the strokes, falling slightly below them like the icon's shadow.
        context.drawLayer { glow in
            glow.addFilter(.blur(radius: mark.lineWidth * 0.5))
            glow.translateBy(x: 0, y: mark.lineWidth * 0.12)
            glow.opacity = timeline.markGlow
            var leftGlow = glow
            leftGlow.opacity *= leftOpacity
            leftGlow.fill(left, with: leftShading)
            var rightGlow = glow
            rightGlow.opacity *= rightOpacity
            rightGlow.fill(right, with: rightShading)
        }
        let sheen = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [.white.opacity(0.24), .white.opacity(0)]),
            startPoint: mark.sheenGradient.start,
            endPoint: mark.sheenGradient.end,
        )
        for (path, shading, opacity) in [(left, leftShading, leftOpacity), (right, rightShading, rightOpacity)] {
            var arch = context
            arch.opacity = opacity
            arch.fill(path, with: shading)
            arch.fill(path, with: sheen)
        }
        if timeline.overlapFill > 0 {
            var overlap = context
            overlap.opacity = timeline.markOpacity * timeline.overlapFill
            overlap.fill(
                mark.overlap,
                with: .linearGradient(
                    Gradient(colors: WelcomeMarkGeometry.overlapColors),
                    startPoint: mark.overlapGradient.start,
                    endPoint: mark.overlapGradient.end,
                ),
            )
            overlap.fill(mark.overlap, with: sheen)
        }
    }

    /// A soft pen of light with a short flare and a trail of glitter while each arch draws. It
    /// grows in as a stroke starts and fades as it ends.
    private func drawPen(in context: GraphicsContext, mark: WelcomeMarkGeometry) {
        let time = timeline.time
        for (side, drawn) in [(WelcomeMarkGeometry.Side.left, timeline.leftArchDrawn), (.right, timeline.rightArchDrawn)] {
            let intensity = timeline.penIntensity(drawn: drawn)
            guard intensity > 0.01 else { continue }
            let tint = Self.penColors[side] ?? .white
            let tip = mark.tip(of: side, drawn: drawn)
            let radius = mark.lineWidth * (0.45 + 0.3 * intensity)
            context.fill(
                circle(tip, radius),
                with: .radialGradient(
                    Gradient(colors: [.white.opacity(0.95 * intensity), tint.opacity(0.45 * intensity), tint.opacity(0)]),
                    center: tip,
                    startRadius: 0,
                    endRadius: radius,
                ),
            )
            let flare = mark.lineWidth * (0.9 + 0.15 * sin(time * 23)) * intensity
            for angle in [0.0, .pi / 2] {
                let offset = CGPoint(x: cos(angle) * flare, y: sin(angle) * flare)
                var ray = Path()
                ray.move(to: CGPoint(x: tip.x - offset.x, y: tip.y - offset.y))
                ray.addLine(to: CGPoint(x: tip.x + offset.x, y: tip.y + offset.y))
                context.stroke(
                    ray,
                    with: .linearGradient(
                        Gradient(colors: [.white.opacity(0), .white.opacity(0.9 * intensity), .white.opacity(0)]),
                        startPoint: CGPoint(x: tip.x - offset.x, y: tip.y - offset.y),
                        endPoint: CGPoint(x: tip.x + offset.x, y: tip.y + offset.y),
                    ),
                    lineWidth: 1.5,
                )
            }
            // Glitter left behind the pen, re-scattered a few times a second.
            let frame = Int(time * 14)
            for index in 1 ... 8 {
                let along = drawn - Double(index) * 0.016
                guard along > 0 else { break }
                let seed = index * 31 + frame * 7 + (side == .left ? 0 : 500)
                let base = mark.tip(of: side, drawn: along)
                let jitter = mark.lineWidth * 0.7
                let point = CGPoint(
                    x: base.x + (welcomeRandom(seed, 1) - 0.5) * jitter,
                    y: base.y + (welcomeRandom(seed, 2) - 0.5) * jitter,
                )
                let fade = (1 - Double(index) / 9) * intensity
                context.fill(circle(point, 1 + 1.6 * welcomeRandom(seed, 3)), with: .color(.white.opacity(0.9 * fade)))
            }
        }
    }

    /// Thin pastel ripples spreading from the icon as it lands.
    private func drawShockwaves(in context: GraphicsContext, mark: WelcomeMarkGeometry, size: CGSize) {
        let reach = max(size.width, size.height) * 0.75
        for (index, ring) in timeline.shockwaves.enumerated() {
            guard let ring else { continue }
            let path = circle(mark.center, mark.frame.width * 0.7 + ring * reach)
            let shading = GraphicsContext.Shading.conicGradient(
                Gradient(colors: Self.ringColors),
                center: mark.center,
                angle: .degrees(timeline.time * 30),
            )
            let width = (index == 0 ? 3 : 1.5) * (1 - ring) + 0.75
            var ringContext = context
            ringContext.opacity = pow(1 - ring, 1.5) * (index == 0 ? 0.6 : 0.35)
            ringContext.drawLayer { glow in
                glow.addFilter(.blur(radius: 10))
                glow.stroke(path, with: shading, lineWidth: width * 5)
            }
            ringContext.stroke(path, with: shading, lineWidth: width)
        }
    }

    /// Pastel sparks drifting out from the icon and fading.
    private func drawSparks(in context: GraphicsContext, mark: WelcomeMarkGeometry, size: CGSize) {
        guard let since = timeline.sinceImpact, since < 2.4 else { return }
        let reach = max(size.width, size.height) * 0.4
        let appear = smoothstep(0, 0.12, since)
        for index in 0 ..< 48 {
            let angle = welcomeRandom(index, 11) * 2 * .pi
            let speed = 0.25 + 0.75 * welcomeRandom(index, 12)
            let life = 1 + 1.4 * welcomeRandom(index, 13)
            let remaining = 1 - since / life
            guard remaining > 0 else { continue }
            let direction = CGPoint(x: cos(angle), y: sin(angle))
            let distance = mark.frame.width * 0.7 + reach * speed * (1 - exp(-since / 0.6))
            let position = CGPoint(x: mark.center.x + direction.x * distance, y: mark.center.y + direction.y * distance)
            let alpha = appear * pow(remaining, 1.4) * 0.8
            let radius = (1.5 + 2 * welcomeRandom(index, 14)) * (0.6 + 0.4 * remaining)
            let color = Self.sparkColors[index % Self.sparkColors.count]
            context.fill(
                circle(position, radius * 4),
                with: .radialGradient(
                    Gradient(colors: [color.opacity(alpha * 0.3), color.opacity(0)]),
                    center: position,
                    startRadius: 0,
                    endRadius: radius * 4,
                ),
            )
            context.fill(circle(position, radius), with: .color(color.opacity(alpha)))
        }
    }

    /// A soft white bloom spreading from behind the icon at the impact.
    private func drawFlash(in context: GraphicsContext, mark: WelcomeMarkGeometry, size: CGSize) {
        let flash = timeline.flash
        guard flash > 0.005 else { return }
        let radius = max(size.width, size.height) * 0.6
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                Gradient(colors: [.white.opacity(min(flash * 1.4, 1)), .white.opacity(flash * 0.35), .white.opacity(0)]),
                center: mark.center,
                startRadius: 0,
                endRadius: radius,
            ),
        )
    }
}
