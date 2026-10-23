import SwiftUI

/// The intro's sky: a dark backdrop, slowly drifting aurora light and a star field that warps
/// forward when the mark lands.
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
        Blob(color: 0x7B5CFF, x: 0.26, y: 0.30, radius: 0.62, speed: 0.11, phase: 0),
        Blob(color: 0x3E8BF0, x: 0.76, y: 0.26, radius: 0.55, speed: 0.09, phase: 1.7),
        Blob(color: 0x1FB8B0, x: 0.66, y: 0.82, radius: 0.58, speed: 0.13, phase: 3.1),
        Blob(color: 0xB25CF0, x: 0.18, y: 0.84, radius: 0.48, speed: 0.07, phase: 4.4),
    ]

    private struct Star {
        let x: Double
        let y: Double
        let depth: Double
        let size: Double
        let twinkle: Double
    }

    private static let stars = (0 ..< 260).map { index in
        Star(
            x: welcomeRandom(index, 1) * 2 - 1,
            y: welcomeRandom(index, 2) * 2 - 1,
            depth: welcomeRandom(index, 3),
            size: 0.6 + welcomeRandom(index, 4) * 1.5,
            twinkle: welcomeRandom(index, 5) * 2 * .pi,
        )
    }

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.opacity = timeline.backdrop
            context.fill(
                Path(rect),
                with: .linearGradient(
                    Gradient(colors: [Color(hex: 0x07060F), Color(hex: 0x120D2B)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height),
                ),
            )
            drawAurora(in: context, size: size)
            drawStars(in: context, size: size)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            context.fill(
                Path(rect),
                with: .radialGradient(
                    Gradient(colors: [.clear, .black.opacity(0.55)]),
                    center: center,
                    startRadius: min(size.width, size.height) * 0.35,
                    endRadius: max(size.width, size.height) * 0.75,
                ),
            )
        }
    }

    private func drawAurora(in context: GraphicsContext, size: CGSize) {
        var context = context
        context.blendMode = .plusLighter
        let time = timeline.time
        let alpha = 0.36 * timeline.auroraIntensity
        for blob in Self.blobs {
            let center = CGPoint(
                x: size.width * (blob.x + 0.07 * sin(time * blob.speed + blob.phase)),
                y: size.height * (blob.y + 0.06 * cos(time * blob.speed * 1.3 + blob.phase)),
            )
            let radius = max(size.width, size.height) * blob.radius * (0.92 + 0.08 * sin(time * 0.3 + blob.phase))
            let color = Color(hex: blob.color)
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                with: .radialGradient(
                    Gradient(colors: [color.opacity(alpha), color.opacity(alpha * 0.35), .clear]),
                    center: center,
                    startRadius: 0,
                    endRadius: radius,
                ),
            )
        }
    }

    private func drawStars(in context: GraphicsContext, size: CGSize) {
        var context = context
        context.blendMode = .plusLighter
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let spread = max(size.width, size.height) * 0.16
        let streak = timeline.warpStreak
        for star in Self.stars {
            let travelled = star.depth - timeline.starTravel
            let depth = travelled - floor(travelled)
            // Near stars are big and bright; each fades out just before it wraps to the back.
            let distance = 0.06 + 0.94 * depth
            let nearness = 1 - depth
            let twinkle = 0.6 + 0.4 * sin(timeline.time * 2.2 + star.twinkle)
            let alpha = pow(nearness, 1.3) * twinkle * timeline.starOpacity * smoothstep(0, 0.08, depth)
            guard alpha > 0.01 else { continue }
            let head = CGPoint(x: center.x + star.x * spread / distance, y: center.y + star.y * spread / distance)
            let radius = star.size * (0.35 + 1.5 * nearness)
            if streak > 0.02 {
                let tailDistance = min(distance + streak * 0.35, 1)
                var trail = Path()
                trail.move(to: CGPoint(x: center.x + star.x * spread / tailDistance, y: center.y + star.y * spread / tailDistance))
                trail.addLine(to: head)
                context.stroke(
                    trail,
                    with: .color(.white.opacity(alpha)),
                    style: StrokeStyle(lineWidth: radius * 1.4, lineCap: .round),
                )
            } else {
                context.fill(
                    Path(ellipseIn: CGRect(x: head.x - radius, y: head.y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(.white.opacity(alpha)),
                )
            }
        }
    }
}

/// The mark drawing itself with a glowing pen, and the burst when it lands: a flash, shockwave
/// rings and sparks flying out.
struct WelcomeBurst: View {
    let timeline: WelcomeIntroTimeline

    private static let sparkColors = [Color.white, Color(hex: 0xC9B8FF), Color(hex: 0x8FD3FF), Color(hex: 0x6FF0DC)]
    private static let ringColors = [
        Color(hex: 0x8E72FF), Color(hex: 0x5AA6F6), Color(hex: 0x2CC9C2), Color(hex: 0xC86BFA), Color(hex: 0x8E72FF),
    ]

    var body: some View {
        Canvas { context, size in
            let mark = WelcomeMarkGeometry(frame: WelcomeIntroScene.markFrame(in: size, timeline: timeline))
            drawHalo(in: context, mark: mark)
            drawMark(in: context, mark: mark)
            drawPen(in: context, mark: mark)
            drawShockwaves(in: context, mark: mark, size: size)
            drawSparks(in: context, mark: mark, size: size)
            drawFlash(in: context, mark: mark, size: size)
        }
    }

    private func circle(_ center: CGPoint, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    /// Soft colored light behind the mark that blooms at the impact.
    private func drawHalo(in context: GraphicsContext, mark: WelcomeMarkGeometry) {
        let presence = timeline.markOpacity * min(timeline.leftArchDrawn * 2, 1)
        guard presence > 0 else { return }
        var context = context
        context.blendMode = .plusLighter
        let center = CGPoint(x: mark.frame.midX, y: mark.frame.midY)
        let radius = mark.frame.width * (1.1 + 0.5 * timeline.impactGlow)
        let alpha = presence * (0.22 + 0.4 * timeline.impactGlow)
        context.fill(
            circle(center, radius),
            with: .radialGradient(
                Gradient(colors: [Color(hex: 0x7B6BFF, opacity: alpha), Color(hex: 0x2CC9C2, opacity: alpha * 0.3), .clear]),
                center: center,
                startRadius: 0,
                endRadius: radius,
            ),
        )
    }

    private func drawMark(in context: GraphicsContext, mark: WelcomeMarkGeometry) {
        var context = context
        context.opacity = timeline.markOpacity
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
        context.drawLayer { glow in
            glow.addFilter(.blur(radius: mark.lineWidth * 0.55))
            glow.opacity = timeline.markGlow
            glow.fill(left, with: leftShading)
            glow.fill(right, with: rightShading)
        }
        context.fill(left, with: leftShading)
        context.fill(right, with: rightShading)
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
        }
        let sheen = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [.white.opacity(0.2), .white.opacity(0)]),
            startPoint: mark.sheenGradient.start,
            endPoint: mark.sheenGradient.end,
        )
        context.fill(left, with: sheen)
        context.fill(right, with: sheen)
    }

    /// A bright pen tip with a flare and a trail of glitter while each arch draws.
    private func drawPen(in context: GraphicsContext, mark: WelcomeMarkGeometry) {
        var context = context
        context.blendMode = .plusLighter
        let time = timeline.time
        for (side, drawn) in [(WelcomeMarkGeometry.Side.left, timeline.leftArchDrawn), (.right, timeline.rightArchDrawn)]
            where drawn > 0 && drawn < 1 {
            let tip = mark.tip(of: side, drawn: drawn)
            let radius = mark.lineWidth * 0.95
            context.fill(
                circle(tip, radius),
                with: .radialGradient(
                    Gradient(colors: [.white.opacity(0.95), Color(hex: 0xBFF2FF, opacity: 0.4), .clear]),
                    center: tip,
                    startRadius: 0,
                    endRadius: radius,
                ),
            )
            let flare = mark.lineWidth * (1.5 + 0.3 * sin(time * 31))
            for angle in [0.0, .pi / 2] {
                let offset = CGPoint(x: cos(angle) * flare, y: sin(angle) * flare)
                var ray = Path()
                ray.move(to: CGPoint(x: tip.x - offset.x, y: tip.y - offset.y))
                ray.addLine(to: CGPoint(x: tip.x + offset.x, y: tip.y + offset.y))
                context.stroke(
                    ray,
                    with: .linearGradient(
                        Gradient(colors: [.clear, .white.opacity(0.9), .clear]),
                        startPoint: CGPoint(x: tip.x - offset.x, y: tip.y - offset.y),
                        endPoint: CGPoint(x: tip.x + offset.x, y: tip.y + offset.y),
                    ),
                    lineWidth: 1.5,
                )
            }
            // Glitter left behind the pen, re-scattered a few times a second.
            let frame = Int(time * 18)
            for index in 1 ... 10 {
                let along = drawn - Double(index) * 0.014
                guard along > 0 else { break }
                let seed = index * 31 + frame * 7 + (side == .left ? 0 : 500)
                let base = mark.tip(of: side, drawn: along)
                let jitter = mark.lineWidth * 0.6
                let point = CGPoint(
                    x: base.x + (welcomeRandom(seed, 1) - 0.5) * jitter,
                    y: base.y + (welcomeRandom(seed, 2) - 0.5) * jitter,
                )
                let fade = 1 - Double(index) / 11
                context.fill(
                    circle(point, 1 + 2 * welcomeRandom(seed, 3)),
                    with: .color(.white.opacity(0.85 * fade)),
                )
            }
        }
    }

    private func drawShockwaves(in context: GraphicsContext, mark: WelcomeMarkGeometry, size: CGSize) {
        var context = context
        context.blendMode = .plusLighter
        let center = CGPoint(x: mark.frame.midX, y: mark.frame.midY)
        let reach = max(size.width, size.height) * 0.85
        for (index, ring) in timeline.shockwaves.enumerated() {
            guard let ring else { continue }
            let path = circle(center, mark.frame.width * 0.45 + ring * reach)
            let shading = GraphicsContext.Shading.conicGradient(
                Gradient(colors: Self.ringColors),
                center: center,
                angle: .degrees(timeline.time * 40),
            )
            let width = (index == 0 ? 14 : 6) * (1 - ring) + 1
            var ringContext = context
            ringContext.opacity = (1 - ring) * (index == 0 ? 0.85 : 0.5)
            ringContext.drawLayer { glow in
                glow.addFilter(.blur(radius: 14))
                glow.stroke(path, with: shading, lineWidth: width * 3)
            }
            ringContext.stroke(path, with: shading, lineWidth: width)
        }
    }

    private func drawSparks(in context: GraphicsContext, mark: WelcomeMarkGeometry, size: CGSize) {
        guard let since = timeline.sinceImpact, since < 2.6 else { return }
        var context = context
        context.blendMode = .plusLighter
        let center = CGPoint(x: mark.frame.midX, y: mark.frame.midY)
        let reach = max(size.width, size.height) * 0.5
        for index in 0 ..< 80 {
            let angle = welcomeRandom(index, 11) * 2 * .pi
            let speed = 0.2 + 0.8 * welcomeRandom(index, 12)
            let life = 0.8 + 1.4 * welcomeRandom(index, 13)
            let remaining = 1 - since / life
            guard remaining > 0 else { continue }
            let direction = CGPoint(x: cos(angle), y: sin(angle))
            let distance = mark.frame.width * 0.55 + reach * speed * (1 - exp(-since / 0.45))
            let position = CGPoint(x: center.x + direction.x * distance, y: center.y + direction.y * distance)
            let velocity = reach * speed / 0.45 * exp(-since / 0.45)
            let alpha = pow(remaining, 1.5)
            let radius = (1.2 + 2.4 * welcomeRandom(index, 14)) * (0.5 + 0.5 * remaining)
            let color = Self.sparkColors[index % Self.sparkColors.count]
            var streak = Path()
            streak.move(to: CGPoint(x: position.x - direction.x * velocity * 0.035, y: position.y - direction.y * velocity * 0.035))
            streak.addLine(to: position)
            context.stroke(streak, with: .color(color.opacity(alpha * 0.8)), style: StrokeStyle(lineWidth: radius * 1.2, lineCap: .round))
            context.fill(circle(position, radius * 3.5), with: .color(color.opacity(alpha * 0.18)))
            context.fill(circle(position, radius), with: .color(color.opacity(alpha)))
        }
    }

    private func drawFlash(in context: GraphicsContext, mark: WelcomeMarkGeometry, size: CGSize) {
        let flash = timeline.flash
        guard flash > 0.005 else { return }
        let center = CGPoint(x: mark.frame.midX, y: mark.frame.midY)
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                Gradient(colors: [.white.opacity(min(flash * 2.4, 1)), .white.opacity(flash * 0.6)]),
                center: center,
                startRadius: 0,
                endRadius: max(size.width, size.height) * 0.7,
            ),
        )
    }
}
