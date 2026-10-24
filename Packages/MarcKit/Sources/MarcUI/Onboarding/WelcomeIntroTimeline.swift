import Foundation

/// Every animated value of the welcome intro as a pure function of time, so the scene renders the
/// same frame for the same moment (on screen, in tests and when exporting frames). The impact at
/// `WelcomeTheme.impactTime` lines up with the soundtrack's boom.
///
/// Nothing switches on in a single frame: every glow, flash and stroke ramps in and out.
/// With Reduce Motion the same story is told with fades only: no drawing, flashes, drift or orbit.
struct WelcomeIntroTimeline {
    let time: Double
    let reduceMotion: Bool

    static let impact = WelcomeTheme.impactTime
    /// When "Get Started" appears.
    static let readyTime = 8.1

    // MARK: Background

    /// The pastel backdrop brightening over the desktop as the window opens.
    var backdrop: Double {
        easeOut(progress(0, 0.8))
    }

    /// How strongly the pastel light shows, lifting a little at the impact.
    var auroraIntensity: Double {
        reduceMotion ? easeOut(progress(0, 1.2)) : easeOut(progress(0.1, 2.2)) * (1 + 0.15 * impactGlow)
    }

    var particleOpacity: Double {
        easeOut(progress(0.4, 1.6)) * (reduceMotion ? 0.6 : 1)
    }

    /// How far the floating particles have drifted outward, in depth units (1 is the whole
    /// field); the impact gives them a gentle push.
    var particleTravel: Double {
        reduceMotion ? 0 : 0.02 * time + 0.22 * smoothstep(Self.impact - 0.1, Self.impact + 1.6, time)
    }

    // MARK: Mark

    var leftArchDrawn: Double {
        reduceMotion ? 1 : easeInOut(progress(1.2, 1.4))
    }

    var rightArchDrawn: Double {
        reduceMotion ? 1 : easeInOut(progress(1.6, 1.4))
    }

    /// An arch fades in over its first few percent, so its round end doesn't pop in as a dot.
    func archOpacity(drawn: Double) -> Double {
        reduceMotion ? 1 : smoothstep(0, 0.05, drawn)
    }

    /// The pen tip grows in as an arch starts and fades away as it finishes.
    func penIntensity(drawn: Double) -> Double {
        reduceMotion ? 0 : smoothstep(0, 0.08, drawn) * (1 - smoothstep(0.86, 1, drawn))
    }

    var markOpacity: Double {
        reduceMotion ? easeOut(progress(0.2, 0.8)) : 1
    }

    /// The lighter shared stem fills in once both arches are drawn.
    var overlapFill: Double {
        reduceMotion ? 1 : easeOut(progress(Self.impact - 0.5, 0.5))
    }

    /// The soft glow that follows the strokes while they draw.
    var drawingGlow: Double {
        reduceMotion ? 1 : smoothstep(1.2, 2.0, time)
    }

    /// The bloom at the impact: it swells over the last third of a second before the boom and
    /// fades out over about a second, instead of switching on at once.
    var impactGlow: Double {
        guard !reduceMotion else { return 0 }
        return smoothstep(Self.impact - 0.35, Self.impact, time) * exp(-max(time - Self.impact, 0) / 0.9)
    }

    /// Strength of the colored glow under the mark.
    var markGlow: Double {
        0.35 * drawingGlow + 0.4 * impactGlow
    }

    /// The white tile of the app icon forms behind the mark as it lands.
    var tile: Double {
        reduceMotion ? easeOut(progress(0.2, 0.8)) : easeOut(progress(Self.impact - 0.12, 1.0))
    }

    /// The mark swells into the impact, then settles and rises above the greeting.
    var markScale: Double {
        if reduceMotion { return 0.5 }
        let swell = 1 + 0.04 * smoothstep(Self.impact - 0.6, Self.impact, time) * (1 - easeOut(progress(Self.impact, 0.6)))
        return swell * (1 - 0.5 * easeInOut(progress(4.3, 1.2)))
    }

    /// Vertical position of the mark's center, as a fraction of the height.
    var markCenterY: Double {
        reduceMotion ? 0.29 : 0.47 - 0.18 * easeInOut(progress(4.3, 1.2))
    }

    // MARK: Impact

    /// A soft white bloom around the mark at the impact.
    var flash: Double {
        guard !reduceMotion else { return 0 }
        return 0.5 * smoothstep(Self.impact - 0.08, Self.impact, time) * exp(-max(time - Self.impact, 0) / 0.35)
    }

    /// Time since the impact, or `nil` before it (sparks drift from the mark from then on).
    var sinceImpact: Double? {
        !reduceMotion && time >= Self.impact ? time - Self.impact : nil
    }

    /// Progress of each expanding ripple, or `nil` while it isn't visible.
    var shockwaves: [Double?] {
        guard !reduceMotion else { return [nil, nil] }
        return [0, 0.18].map { delay in
            let ring = progress(Self.impact + delay, 1.8)
            return ring > 0 && ring < 1 ? easeOut(ring) : nil
        }
    }

    // MARK: Greeting

    /// Appearance of letter `index` of the title, 0...1.
    func titleLetter(_ index: Int) -> Double {
        reduceMotion ? easeOut(progress(1.0, 0.8)) : easeOut(progress(4.9 + Double(index) * 0.045, 0.8))
    }

    /// A glow sweeping across the title once it has settled, -1 (before) ... 2 (after).
    var titleSheen: Double {
        reduceMotion ? 2 : -1 + 3 * easeInOut(progress(6.2, 1.6))
    }

    var subtitle: Double {
        reduceMotion ? easeOut(progress(1.4, 0.8)) : easeOut(progress(6.2, 0.9))
    }

    // MARK: Space cards

    static let cardCount = 6

    /// How far card `index` has floated out from the center, 0...1.
    func cardAppearance(_ index: Int) -> Double {
        reduceMotion ? easeOut(progress(1.6, 0.8)) : easeOut(progress(5.6 + Double(index) * 0.12, 1.4))
    }

    /// Card `index`'s angle on the orbit; the ring turns slowly.
    func cardAngle(_ index: Int) -> Double {
        Double(index) / Double(Self.cardCount) * 2 * .pi + (reduceMotion ? 0 : time * 0.02)
    }

    func cardFloat(_ index: Int) -> Double {
        reduceMotion ? 0 : sin(time * 0.8 + Double(index))
    }

    // MARK: Call to action

    var button: Double {
        reduceMotion ? easeOut(progress(2.0, 0.6)) : easeOutBack(progress(Self.readyTime, 0.8))
    }

    var buttonPulse: Double {
        reduceMotion ? 0 : sin(time * 2.6)
    }

    var hint: Double {
        easeOut(progress(reduceMotion ? 2.6 : Self.readyTime + 0.7, 0.6))
    }

    var controls: Double {
        easeOut(progress(0.6, 0.6))
    }

    // MARK: Easing

    private func progress(_ start: Double, _ duration: Double) -> Double {
        min(max((time - start) / duration, 0), 1)
    }

    private func easeOut(_ x: Double) -> Double {
        1 - pow(1 - x, 3)
    }

    private func easeInOut(_ x: Double) -> Double {
        x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }

    /// Overshoots slightly before settling, for things that pop in.
    private func easeOutBack(_ x: Double) -> Double {
        guard x > 0 else { return 0 }
        let c1 = 1.70158, c3 = c1 + 1
        return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
    }
}

/// Progress of the exit (zoom, blur and fade) after "Get Started", 0...1.
func welcomeExitProgress(_ elapsed: Double?) -> Double {
    guard let elapsed else { return 0 }
    let x = min(max(elapsed / WelcomeIntroModel.exitDuration, 0), 1)
    return x * x * (3 - 2 * x)
}
