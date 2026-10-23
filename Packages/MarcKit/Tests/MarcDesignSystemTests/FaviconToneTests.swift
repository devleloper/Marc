import AppKit
import Testing
@testable import MarcDesignSystem

struct FaviconToneTests {
    /// Draws a 32 × 32 icon: a filled circle on a transparent background, optionally with a
    /// contrasting square in the middle.
    func icon(_ fill: NSColor, glyph: NSColor? = nil) -> NSImage {
        NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            fill.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2)).fill()
            if let glyph {
                glyph.setFill()
                NSBezierPath(rect: rect.insetBy(dx: 10, dy: 10)).fill()
            }
            return true
        }
    }

    @Test func `black single-color icon is dark`() {
        #expect(FaviconTone.monochromeTone(of: icon(.black)) == .dark)
    }

    @Test func `white single-color icon is light`() {
        #expect(FaviconTone.monochromeTone(of: icon(.white)) == .light)
    }

    @Test func `colored icon has no monochrome tone`() {
        #expect(FaviconTone.monochromeTone(of: icon(.systemOrange)) == nil)
    }

    @Test func `dark tile with a light glyph keeps its own contrast`() {
        #expect(FaviconTone.monochromeTone(of: icon(.black, glyph: .white)) == nil)
    }

    @Test func `mid gray icon is left alone`() {
        #expect(FaviconTone.monochromeTone(of: icon(NSColor(white: 0.5, alpha: 1))) == nil)
    }
}
