import AppKit
import Testing
@testable import MenuBarStatsUI

@MainActor
@Test("Raw image fingerprints detect changed graph pixels and preserve Retina size and template mode")
func rawImageFingerprint() throws {
    func image(_ x: CGFloat) -> NSImage {
        let value = NSImage(size: NSSize(width: 20, height: 22), flipped: false) { _ in
            NSColor.white.setFill()
            NSRect(x: x, y: 2, width: 0.5, height: 15).fill()
            return true
        }
        value.isTemplate = true
        return value
    }
    let first = StatusItemRendering.preparedImage(image(1), scale: 2)
    let same = StatusItemRendering.preparedImage(image(1), scale: 2)
    let moved = StatusItemRendering.preparedImage(image(1.5), scale: 2)
    #expect(first.fingerprint != nil)
    #expect(first.fingerprint == same.fingerprint)
    #expect(first.fingerprint != moved.fingerprint)
    #expect(first.image.size == NSSize(width: 20, height: 22))
    #expect(first.image.isTemplate)
    let bitmap = try #require(first.image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    #expect(bitmap.width == 40)
    #expect(bitmap.height == 44)
}
