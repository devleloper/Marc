import AVFoundation
import Foundation
import Testing
@testable import MarcUI

struct WelcomeThemeTests {
    static let sampleRate = 48000.0

    /// Renders `seconds` of the theme into two channels.
    func render(seconds: Double) -> (left: [Float], right: [Float]) {
        let theme = WelcomeTheme(sampleRate: Self.sampleRate)
        let count = Int(seconds * Self.sampleRate)
        var left = [Float](repeating: 0, count: count)
        var right = [Float](repeating: 0, count: count)
        left.withUnsafeMutableBufferPointer { leftBuffer in
            right.withUnsafeMutableBufferPointer { rightBuffer in
                var offset = 0
                while offset < count {
                    let frames = min(512, count - offset)
                    theme.render(left: leftBuffer.baseAddress! + offset, right: rightBuffer.baseAddress! + offset, frames: frames)
                    offset += frames
                }
            }
        }
        return (left, right)
    }

    func rms(_ samples: ArraySlice<Float>) -> Float {
        (samples.reduce(0) { $0 + $1 * $1 } / Float(max(samples.count, 1))).squareRoot()
    }

    func window(_ samples: [Float], from start: Double, to end: Double) -> ArraySlice<Float> {
        samples[Int(start * Self.sampleRate) ..< Int(end * Self.sampleRate)]
    }

    @Test func `the theme stays within range and never produces NaN`() {
        let (left, right) = render(seconds: 16)
        for channel in [left, right] {
            #expect(!channel.contains { $0.isNaN || $0.isInfinite })
            #expect(channel.map(abs).max() ?? 0 < 1)
        }
    }

    @Test func `the intro swells, hits at the impact and keeps playing`() {
        let (left, _) = render(seconds: 16)
        let opening = rms(window(left, from: 0, to: 0.5))
        let swell = rms(window(left, from: 2.5, to: 3.4))
        let impact = rms(window(left, from: WelcomeTheme.impactTime, to: WelcomeTheme.impactTime + 0.4))
        let loop = rms(window(left, from: 10, to: 16))
        #expect(opening < swell, "The pad fades in")
        #expect(impact > swell, "The impact is the loudest moment")
        #expect(loop > 0.02, "The loop keeps playing after the intro")
    }

    /// Writes the first 20 seconds, with the app's echo and reverb, to `MARC_WELCOME_AUDIO` (a .wav
    /// path) for listening.
    @Test func `exports the theme for listening`() throws {
        guard let path = ProcessInfo.processInfo.environment["MARC_WELCOME_AUDIO"] else { return }
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 2))
        let engine = AVAudioEngine()
        WelcomeSoundtrack.connect(WelcomeTheme(sampleRate: Self.sampleRate), to: engine, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        try engine.start()
        let file = try AVAudioFile(forWriting: URL(fileURLWithPath: path), settings: format.settings)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096))
        let total = AVAudioFramePosition(20 * Self.sampleRate)
        while engine.manualRenderingSampleTime < total {
            let frames = min(AVAudioFrameCount(total - engine.manualRenderingSampleTime), buffer.frameCapacity)
            #expect(try engine.renderOffline(frames, to: buffer) == .success)
            try file.write(from: buffer)
        }
        engine.stop()
    }
}
