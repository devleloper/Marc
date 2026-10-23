import AVFoundation
import Foundation
import os

/// The welcome intro's music, synthesized while it plays: an original theme, so nothing is
/// bundled or licensed. A soft Dadd9 pad swells under a filtered-noise riser; when the logo lands
/// (`impactTime`) a low boom and a bell chord hit, then a four-chord loop (Gmaj9, D/F♯, Bm9, Aadd9 at
/// 84 BPM) carries a pad, a bass line and an arpeggio for as long as the intro stays open.
///
/// Rendering is pure math on the audio thread: oscillators are computed from absolute time, and
/// the only state (noise and its filter) is touched by the render thread alone.
final nonisolated class WelcomeTheme: @unchecked Sendable {
    static let impactTime = 3.5
    static let beat = 60.0 / 84
    static let bar = beat * 4

    private struct Chord {
        let bass: Double
        let pad: [Double]
        let arpeggio: [Double]
    }

    private let sampleRate: Double
    private var frame = 0
    private var noiseState: UInt32 = 0x9E37_79B9
    private var noiseFiltered = 0.0

    private let introChord = Chord(bass: 0, pad: [62, 64, 66, 69].map(hertz), arpeggio: [])
    private let progression: [Chord] = [
        Chord(bass: hertz(43), pad: [62, 66, 69, 71].map(hertz), arpeggio: [67, 71, 74, 78].map(hertz)),
        Chord(bass: hertz(42), pad: [61, 66, 69, 74].map(hertz), arpeggio: [62, 66, 69, 73].map(hertz)),
        Chord(bass: hertz(47), pad: [61, 62, 66, 69].map(hertz), arpeggio: [59, 62, 66, 73].map(hertz)),
        Chord(bass: hertz(45), pad: [59, 61, 64, 69].map(hertz), arpeggio: [57, 61, 64, 71].map(hertz)),
    ]
    private let bell = [74, 78, 81, 86].map(hertz)
    private let arpeggioPattern = [0, 1, 2, 3, 2, 3, 1, 2]

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }

    /// Renders the next `frames` samples of each channel.
    func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
        for index in 0 ..< frames {
            let (partLeft, partRight) = sample(at: Double(frame) / sampleRate)
            left[index] = Float(tanh(partLeft) * 0.85)
            right[index] = Float(tanh(partRight) * 0.85)
            frame += 1
        }
    }

    private func sample(at t: Double) -> (Double, Double) {
        var left = 0.0, right = 0.0
        let impact = Self.impactTime

        // Intro pad, swelling in and handing over to the loop after the impact.
        if t < impact + 1.6 {
            let gain = smoothstep(0, 2.6, t) * (1 - smoothstep(impact, impact + 1.6, t)) * 0.9
            let (partLeft, partRight) = pad(introChord.pad, at: t)
            left += partLeft * gain
            right += partRight * gain
        }

        // Riser: noise opening up from 300 Hz to 7 kHz as the mark draws.
        if t >= 1, t < impact {
            let progress = (t - 1) / (impact - 1)
            let cutoff = 300 * pow(7000.0 / 300, progress)
            let coefficient = 1 - exp(-2 * .pi * cutoff / sampleRate)
            noiseFiltered += coefficient * (noise() - noiseFiltered)
            let value = noiseFiltered * 0.16 * progress * progress
            left += value
            right += value
        }

        if t >= impact {
            let since = t - impact
            if since < 6 {
                let (partLeft, partRight) = hit(at: since)
                left += partLeft
                right += partRight
            }
            let (partLeft, partRight) = groove(at: since)
            left += partLeft
            right += partRight
        }
        return (left, right)
    }

    /// Low boom sweeping down from 120 Hz, plus an inharmonic bell chord.
    private func hit(at since: Double) -> (Double, Double) {
        let boomPhase = 2 * .pi * (40 * since + 80 * 0.25 * (1 - exp(-since / 0.25)))
        let boom = sin(boomPhase) * 0.65 * exp(-since / 0.55) * (1 - exp(-since / 0.005))
        var left = boom, right = boom
        for (index, frequency) in bell.enumerated() {
            let tone = sin(2 * .pi * frequency * since) * exp(-since / 2.2)
                + 0.3 * sin(2 * .pi * frequency * 2.76 * since) * exp(-since / 0.8)
            let value = tone * 0.05 * (1 - exp(-since / 0.003))
            let pan = index.isMultiple(of: 2) ? 0.35 : -0.35
            left += value * (1 - pan)
            right += value * (1 + pan)
        }
        return (left, right)
    }

    private func groove(at since: Double) -> (Double, Double) {
        let bars = since / Self.bar
        let barIndex = Int(bars)
        let withinBar = since - Double(barIndex) * Self.bar
        let chord = progression[barIndex % progression.count]
        var left = 0.0, right = 0.0

        // Pad: crossfade from the previous chord.
        let entry = barIndex == 0 ? smoothstep(0, 1.4, withinBar) : smoothstep(0, 0.8, withinBar)
        var (partLeft, partRight) = pad(chord.pad, at: since)
        left += partLeft * entry
        right += partRight * entry
        if barIndex > 0 {
            let fade = 1 - smoothstep(0, 1.2, withinBar)
            if fade > 0 {
                (partLeft, partRight) = pad(progression[(barIndex - 1) % progression.count].pad, at: since)
                left += partLeft * fade
                right += partRight * fade
            }
        }

        // Bass: a soft pluck that settles into a sustain.
        let bassEnvelope = (1 - exp(-withinBar / 0.03)) * (0.6 + 0.4 * exp(-withinBar / 1.5))
        let bass = (sin(2 * .pi * chord.bass * since) + 0.3 * sin(4 * .pi * chord.bass * since)) * 0.16 * bassEnvelope
        left += bass
        right += bass

        // Arpeggio in eighth notes, alternating sides; the previous note's tail rings into the next.
        let step = Self.beat / 2
        let stepIndex = Int(since / step)
        let withinStep = since - Double(stepIndex) * step
        for (offset, age) in [(0, withinStep), (1, withinStep + step)] where stepIndex - offset >= 0 {
            let index = stepIndex - offset
            let stepChord = progression[Int(Double(index) * step / Self.bar) % progression.count]
            let frequency = stepChord.arpeggio[arpeggioPattern[index % arpeggioPattern.count]]
            let envelope = exp(-age / 0.28) * (1 - exp(-age / 0.004))
            let tone = sin(2 * .pi * frequency * since) + 0.25 * sin(4 * .pi * frequency * since)
                + 0.1 * sin(6 * .pi * frequency * since)
            let value = tone * 0.09 * envelope * smoothstep(0, 1.0, since)
            let pan = index.isMultiple(of: 2) ? 0.35 : -0.35
            left += value * (1 - pan)
            right += value * (1 + pan)
        }
        return (left, right)
    }

    /// A slow-breathing pad: each note is a slightly detuned pair spread across the stereo field.
    private func pad(_ notes: [Double], at t: Double) -> (Double, Double) {
        let breath = 0.85 + 0.15 * sin(2 * .pi * 0.2 * t)
        var left = 0.0, right = 0.0
        for frequency in notes {
            let center = sin(2 * .pi * frequency * t) + 0.25 * sin(4 * .pi * frequency * t)
            left += (center + 0.6 * sin(2 * .pi * frequency * 1.004 * t)) * 0.04
            right += (center + 0.6 * sin(2 * .pi * frequency * 0.996 * t)) * 0.04
        }
        return (left * breath, right * breath)
    }

    private func noise() -> Double {
        noiseState ^= noiseState << 13
        noiseState ^= noiseState >> 17
        noiseState ^= noiseState << 5
        return Double(noiseState) / Double(UInt32.max) * 2 - 1
    }
}

private nonisolated func hertz(_ midiNote: Int) -> Double {
    440 * pow(2, Double(midiNote - 69) / 12)
}

nonisolated func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
    let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}

/// Plays `WelcomeTheme` through AVAudioEngine with a hall reverb and a dotted-eighth echo.
@MainActor
final class WelcomeSoundtrack {
    private let engine = AVAudioEngine()
    private var fadeTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "dev.devleloper.Marc", category: "WelcomeSoundtrack")
    private static let volume: Float = 0.9

    var isMuted = false {
        didSet { fade(to: isMuted ? 0 : Self.volume, over: 0.3) }
    }

    func start() {
        guard !engine.isRunning, let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2) else { return }
        Self.connect(WelcomeTheme(sampleRate: format.sampleRate), to: engine, format: format)
        engine.mainMixerNode.outputVolume = 0
        do {
            try engine.start()
            fade(to: isMuted ? 0 : Self.volume, over: 0.8)
        } catch {
            // No output device (for example on a CI machine): the intro simply plays silently.
            logger.error("Could not start the welcome soundtrack: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Fades out, then stops the engine.
    func stop(over duration: Double = 0.8) {
        fade(to: 0, over: duration) { [engine] in engine.stop() }
    }

    /// The theme into the engine's main mixer: dry, plus a dotted-eighth echo and a large hall fed
    /// through a 200 Hz high-pass send. Keeping the bass out of the effects matters: the echo's
    /// feedback otherwise resonates with some bass notes and pumps the loop. Also used to render the
    /// theme offline.
    nonisolated static func connect(_ theme: WelcomeTheme, to engine: AVAudioEngine, format: AVAudioFormat) {
        let source = makeSource(theme: theme, format: format)
        let send = AVAudioUnitEQ(numberOfBands: 1)
        send.bands[0].filterType = .highPass
        send.bands[0].frequency = 200
        send.bands[0].bypass = false
        let delay = AVAudioUnitDelay()
        delay.delayTime = WelcomeTheme.beat * 0.75
        delay.feedback = 25
        delay.lowPassCutoff = 6000
        delay.wetDryMix = 100
        let reverb = AVAudioUnitReverb()
        reverb.loadFactoryPreset(.largeHall2)
        reverb.wetDryMix = 100
        let echoLevel = AVAudioMixerNode()
        echoLevel.outputVolume = 0.25
        let hallLevel = AVAudioMixerNode()
        hallLevel.outputVolume = 0.5
        for node in [source, send, delay, reverb, echoLevel, hallLevel] as [AVAudioNode] {
            engine.attach(node)
        }
        let main = engine.mainMixerNode
        engine.connect(
            source,
            to: [AVAudioConnectionPoint(node: main, bus: 0), AVAudioConnectionPoint(node: send, bus: 0)],
            fromBus: 0,
            format: format,
        )
        engine.connect(
            send,
            to: [AVAudioConnectionPoint(node: delay, bus: 0), AVAudioConnectionPoint(node: reverb, bus: 0)],
            fromBus: 0,
            format: format,
        )
        engine.connect(delay, to: echoLevel, format: format)
        engine.connect(reverb, to: hallLevel, format: format)
        engine.connect(echoLevel, to: main, fromBus: 0, toBus: 1, format: format)
        engine.connect(hallLevel, to: main, fromBus: 0, toBus: 2, format: format)
    }

    /// The render block runs on the audio thread, so it must not inherit the main actor.
    private nonisolated static func makeSource(theme: WelcomeTheme, format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self)
            else { return noErr }
            theme.render(left: left, right: right, frames: Int(frameCount))
            return noErr
        }
    }

    private func fade(to target: Float, over duration: Double, then completion: (@MainActor () -> Void)? = nil) {
        fadeTask?.cancel()
        let mixer = engine.mainMixerNode
        let start = mixer.outputVolume
        fadeTask = Task {
            let steps = max(Int(duration * 60), 1)
            for step in 1 ... steps {
                try? await Task.sleep(for: .milliseconds(16))
                if Task.isCancelled { return }
                mixer.outputVolume = start + (target - start) * Float(step) / Float(steps)
            }
            completion?()
        }
    }
}
