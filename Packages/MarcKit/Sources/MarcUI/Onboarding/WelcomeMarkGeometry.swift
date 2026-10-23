import CoreGraphics
import SwiftUI

/// The "m" of Marc's icon (design/render-icons.swift) as paths the intro can draw stroke by stroke.
/// Coordinates are the icon's, cropped to the mark: a 564 × 548 box holding two arches 124 units
/// wide that share the middle stem.
struct WelcomeMarkGeometry {
    static let size = CGSize(width: 564, height: 548)
    static let aspectRatio = size.height / size.width

    /// Where the mark sits and how big it is on screen.
    let frame: CGRect

    var scale: CGFloat {
        frame.width / Self.size.width
    }

    var lineWidth: CGFloat {
        124 * scale
    }

    var center: CGPoint {
        CGPoint(x: frame.midX, y: frame.midY)
    }

    /// One arch's centerline: up the left leg, over the top, down the right leg.
    struct Arch {
        let left: CGFloat
        let right: CGFloat
        let top: CGFloat = 62
        let bottom: CGFloat = 486

        var radius: CGFloat {
            (right - left) / 2
        }

        var leg: CGFloat {
            bottom - (top + radius)
        }

        var length: CGFloat {
            2 * leg + .pi * radius
        }

        /// The point `fraction` of the way along the centerline, in mark units.
        func point(at fraction: Double) -> CGPoint {
            let distance = CGFloat(min(max(fraction, 0), 1)) * length
            let centerY = top + radius
            if distance < leg {
                return CGPoint(x: left, y: bottom - distance)
            }
            if distance < leg + .pi * radius {
                let angle = .pi + (distance - leg) / radius
                return CGPoint(x: left + radius + radius * cos(angle), y: centerY + radius * sin(angle))
            }
            return CGPoint(x: right, y: centerY + distance - leg - .pi * radius)
        }

        var path: Path {
            Path { path in
                path.move(to: point(at: 0))
                for step in 1 ... 120 {
                    path.addLine(to: point(at: Double(step) / 120))
                }
            }
        }
    }

    enum Side {
        case left
        case right

        var arch: Arch {
            switch self {
            case .left: Arch(left: 62, right: 282)
            case .right: Arch(left: 282, right: 502)
            }
        }
    }

    /// Outlines are stroked with Core Graphics, as the icon is: SwiftUI's `strokedPath` comes back
    /// empty from `intersection`.
    private static func outline(_ path: Path) -> Path {
        Path(path.cgPath.copy(strokingWithWidth: 124, lineCap: .round, lineJoin: .round, miterLimit: 10))
    }

    private static let unitStrokes = (left: outline(Side.left.arch.path), right: outline(Side.right.arch.path))
    private static let unitOverlap = Path(unitStrokes.left.cgPath.intersection(unitStrokes.right.cgPath))

    /// Maps mark units to the screen.
    var transform: CGAffineTransform {
        CGAffineTransform(translationX: frame.minX, y: frame.minY).scaledBy(x: scale, y: scale)
    }

    func point(_ unit: CGPoint) -> CGPoint {
        unit.applying(transform)
    }

    func tip(of side: Side, drawn: Double) -> CGPoint {
        point(side.arch.point(at: drawn))
    }

    /// The outline of an arch drawn `drawn` of the way, ready to fill.
    func stroke(of side: Side, drawn: Double) -> Path {
        let unit = if drawn >= 1 {
            side == .left ? Self.unitStrokes.left : Self.unitStrokes.right
        } else {
            Self.outline(side.arch.path.trimmedPath(from: 0, to: drawn))
        }
        return unit.applying(transform)
    }

    /// The shared stem, filled with the lighter "aurora" blue.
    var overlap: Path {
        Self.unitOverlap.applying(transform)
    }

    // MARK: Colors (the Aurora icon's)

    static let leftColors = [Color(hex: 0xA58BFF), Color(hex: 0x6A4CF0)]
    static let rightColors = [Color(hex: 0x4BE3CD), Color(hex: 0x1BB0D0)]
    static let overlapColors = [Color(hex: 0xBFF2FF), Color(hex: 0x7AC7FC)]

    var leftGradient: (start: CGPoint, end: CGPoint) {
        (point(CGPoint(x: 30, y: 44)), point(CGPoint(x: 330, y: 524)))
    }

    var rightGradient: (start: CGPoint, end: CGPoint) {
        (point(CGPoint(x: 250, y: 44)), point(CGPoint(x: 550, y: 524)))
    }

    var overlapGradient: (start: CGPoint, end: CGPoint) {
        (point(CGPoint(x: 282, y: 62)), point(CGPoint(x: 282, y: 548)))
    }

    var sheenGradient: (start: CGPoint, end: CGPoint) {
        (point(CGPoint(x: 282, y: 44)), point(CGPoint(x: 282, y: 304)))
    }
}

extension Color {
    /// A color from a 0xRRGGBB literal.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity,
        )
    }
}

/// A repeatable pseudo-random number in 0..<1 for `index` (and `salt`, to draw several per index),
/// so the stars and sparks sit in the same places on every frame.
func welcomeRandom(_ index: Int, _ salt: Int) -> Double {
    var value = UInt64(truncatingIfNeeded: index) &* 0x9E37_79B9_7F4A_7C15 &+ UInt64(truncatingIfNeeded: salt) &* 0xD1B5_4A32_D192_ED03
    value ^= value >> 30
    value = value &* 0xBF58_476D_1CE4_E5B9
    value ^= value >> 27
    value = value &* 0x94D0_49BB_1331_11EB
    value ^= value >> 31
    return Double(value >> 11) / Double(UInt64(1) << 53)
}
