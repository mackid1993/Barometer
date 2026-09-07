import AppKit
import Testing
@testable import MenuBarStatsUI

@Suite("SystemClockCoverTests")
@MainActor
struct SystemClockCoverTests {
    @Test("the band test keeps a clock on the bar and rejects one that drifted or grew")
    func band() {
        let display = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        #expect(SystemClockCover.boundsAreInBand(
            CGRect(x: 1554, y: 5.5, width: 150, height: 22), displayBounds: display, barHeight: 33))
        #expect(!SystemClockCover.boundsAreInBand(
            CGRect(x: 1554, y: 200, width: 150, height: 22), displayBounds: display, barHeight: 33))
        #expect(!SystemClockCover.boundsAreInBand(
            CGRect(x: 1554, y: 0, width: 150, height: 90), displayBounds: display, barHeight: 33))
    }

    @Test("top-left global bounds flip into a bottom-left Cocoa frame")
    func flip() {
        let rect = SystemClockCover.cocoaRect(from: CGRect(x: 1554, y: 5.5, width: 150, height: 22), primaryHeight: 1117)
        #expect(rect == CGRect(x: 1554, y: 1117 - 27.5, width: 150, height: 22))
        #expect(SystemClockCover.cocoaRect(from: .zero, primaryHeight: nil) == nil)
    }
}
