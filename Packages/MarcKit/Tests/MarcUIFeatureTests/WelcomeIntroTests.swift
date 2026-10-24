import AppKit
import Foundation
import SwiftUI
import Testing
@testable import MarcUI

struct WelcomeIntroTests {
    func timeline(_ time: Double, reduceMotion: Bool = false) -> WelcomeIntroTimeline {
        WelcomeIntroTimeline(time: time, reduceMotion: reduceMotion)
    }

    @Test func `the mark is drawn by the time it lands`() {
        let impact = WelcomeTheme.impactTime
        #expect(timeline(0.5).leftArchDrawn == 0)
        #expect(timeline(2).leftArchDrawn > 0)
        #expect(timeline(impact).leftArchDrawn == 1)
        #expect(timeline(impact).rightArchDrawn == 1)
    }

    @Test func `the impact blooms in time with the music`() {
        let impact = WelcomeTheme.impactTime
        #expect(timeline(impact - 0.2).flash == 0)
        #expect(timeline(impact).flash > 0.4)
        #expect(timeline(impact + 2).flash < 0.01)
        #expect(timeline(impact - 0.5).tile == 0)
        #expect(timeline(impact + 1).tile > 0.95)
        #expect(timeline(impact + 0.3).shockwaves.contains { $0 != nil })
        #expect(timeline(impact + 2).shockwaves.allSatisfy { $0 == nil })
    }

    @Test func `the greeting and button arrive in order`() {
        let ready = WelcomeIntroTimeline.readyTime
        #expect(timeline(4).titleLetter(0) == 0)
        #expect(timeline(6.5).titleLetter(WelcomeTitleRenderer.glyphCount - 1) == 1)
        #expect(timeline(ready - 0.1).button == 0)
        #expect(abs(timeline(ready + 1).button - 1) < 0.001)
    }

    @Test func `reduce motion replaces movement with fades`() {
        let calm = timeline(3.6, reduceMotion: true)
        #expect(calm.flash == 0)
        #expect(calm.impactGlow == 0)
        #expect(calm.particleTravel == 0)
        #expect(calm.shockwaves.allSatisfy { $0 == nil })
        #expect(calm.leftArchDrawn == 1)
        #expect(timeline(3, reduceMotion: true).button == 1)
    }

    /// Glows ramp instead of switching on: no value may jump between two frames at 120 Hz.
    @Test func `glows never jump between frames`() {
        let step = 1.0 / 120
        for frame in 0 ..< 1500 {
            let now = timeline(Double(frame) * step), next = timeline(Double(frame + 1) * step)
            let pairs: [(Double, Double)] = [
                (now.markGlow, next.markGlow),
                (now.impactGlow, next.impactGlow),
                (now.flash, next.flash),
                (now.penIntensity(drawn: now.leftArchDrawn), next.penIntensity(drawn: next.leftArchDrawn)),
                (now.archOpacity(drawn: now.rightArchDrawn), next.archOpacity(drawn: next.rightArchDrawn)),
                (now.tile, next.tile),
            ]
            for (current, upcoming) in pairs {
                #expect(abs(upcoming - current) < 0.08, "Jump at \(Double(frame) * step) s")
            }
        }
    }

    @Test func `the exit eases from 0 to 1`() {
        #expect(welcomeExitProgress(nil) == 0)
        #expect(welcomeExitProgress(0) == 0)
        #expect(welcomeExitProgress(WelcomeIntroModel.exitDuration / 2) == 0.5)
        #expect(welcomeExitProgress(WelcomeIntroModel.exitDuration * 2) == 1)
    }

    @Test func `the mark's overlap is the shared stem`() {
        let mark = WelcomeMarkGeometry(frame: CGRect(origin: .zero, size: WelcomeMarkGeometry.size))
        let stem = mark.overlap.boundingRect
        #expect(abs(stem.midX - 282) < 1)
        #expect(stem.width <= 125)
        #expect(stem.maxY > 540)
        let leftEnd = mark.tip(of: .left, drawn: 1), rightStart = mark.tip(of: .right, drawn: 0)
        #expect(abs(leftEnd.x - 282) < 0.01 && abs(leftEnd.y - 486) < 0.01)
        #expect(abs(rightStart.x - 282) < 0.01 && abs(rightStart.y - 486) < 0.01)
    }

    /// Writes PNGs of key moments to `MARC_WELCOME_FRAMES` (a directory) for review. With
    /// `MARC_WELCOME_FPS` it writes every frame of the first 13 seconds instead, leaving at 12 s, to
    /// make a video.
    @Test func `exports frames for review`() throws {
        guard let directory = ProcessInfo.processInfo.environment["MARC_WELCOME_FRAMES"] else { return }
        let url = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let fps = ProcessInfo.processInfo.environment["MARC_WELCOME_FPS"].flatMap(Double.init)
        let leaving = 12.0
        let times = fps.map { fps in Array(stride(from: 0, to: leaving + 1, by: 1 / fps)) }
            ?? [0.6, 1.8, 2.6, 3.3, 3.55, 3.8, 4.4, 5.2, 6.0, 6.6, 9.0, 14.0]
        for (index, time) in times.enumerated() {
            let scene = WelcomeIntroScene(
                timeline: WelcomeIntroTimeline(time: time, reduceMotion: false),
                exit: fps == nil ? 0 : welcomeExitProgress(time > leaving ? time - leaving : nil),
            )
            .frame(width: fps == nil ? 1512 : 1280, height: fps == nil ? 945 : 800)
            .background(.black)
            let renderer = ImageRenderer(content: scene)
            renderer.scale = 1
            let image = try #require(renderer.cgImage)
            let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            let name = fps == nil ? String(format: "welcome-%05.2f.png", time) : String(format: "frame-%04d.png", index)
            try data.write(to: url.appending(path: name))
        }
    }
}
