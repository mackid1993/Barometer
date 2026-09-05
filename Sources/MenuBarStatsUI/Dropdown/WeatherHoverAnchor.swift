import AppKit
import SwiftUI

/// Provides a stable row anchor and native hover events without entering a menu-tracking loop.
struct WeatherHoverAnchor: NSViewRepresentable {
    let show: @MainActor (NSView) -> Void

    func makeNSView(context: Context) -> HoverView { HoverView() }
    func updateNSView(_ view: HoverView, context: Context) { view.show = show }

    final class HoverView: NSView {
        var show: (@MainActor (NSView) -> Void)?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            addTrackingArea(NSTrackingArea(rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
        }

        override func mouseEntered(with event: NSEvent) { show?(self) }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
