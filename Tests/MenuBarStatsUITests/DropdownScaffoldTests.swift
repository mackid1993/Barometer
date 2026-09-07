import AppKit
import SwiftUI
import Testing
@testable import MenuBarStatsUI

@Suite("Dropdown scaffold width", .serialized)
@MainActor
struct DropdownScaffoldTests {
    /// A card must sit the same distance from both sides of the scroll view's visible area. Pinning the
    /// content to the panel width made it overflow by the scroller's width wherever macOS shows legacy scroll
    /// bars, and the overflow was centered, so every card slid half a scroller to the left.
    @Test("Cards keep equal padding on both sides of the visible area")
    func cardsKeepEqualPadding() throws {
        let size = CGSize(width: 380, height: 160)
        let view = DropdownScaffold(size: size) { GlassCard { Color.red.frame(height: 40) } }
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)

        let scale = CGFloat(rep.pixelsWide) / size.width
        var first = -1
        var last = -1
        for x in 0..<rep.pixelsWide {
            guard let color = rep.colorAt(x: x, y: rep.pixelsHigh / 3) else { continue }
            guard color.redComponent > 0.6, color.greenComponent < 0.4, color.blueComponent < 0.4 else { continue }
            if first < 0 { first = x }
            last = x
        }
        try #require(first >= 0, "the card did not render")

        let reserved =
            NSScroller.preferredScrollerStyle == .legacy
            ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0
        let inset = BarometerDesign.panelPadding + BarometerDesign.cardPadding
        #expect(abs(CGFloat(first) / scale - inset) < 1)
        #expect(abs(size.width - reserved - CGFloat(last + 1) / scale - inset) < 1)
    }
}
