import AppKit
import SwiftUI

/// Provides a stable row anchor and native hover events without entering a menu-tracking loop.
struct WeatherHoverAnchor: NSViewRepresentable {
    let show: @MainActor (NSView) -> Void
    let hide: @MainActor (NSView) -> Void

    func makeNSView(context: Context) -> HoverView { HoverView() }
    func updateNSView(_ view: HoverView, context: Context) {
        view.show = show
        view.hide = hide
    }

    final class HoverView: NSView {
        private static let hoverIntentDelay: TimeInterval = 0.15

        var show: (@MainActor (NSView) -> Void)?
        var hide: (@MainActor (NSView) -> Void)?
        private var presentationTimer: Timer?
        private var isPointerInside = false

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            addTrackingArea(NSTrackingArea(rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
        }

        override func mouseEntered(with event: NSEvent) {
            isPointerInside = true
            presentationTimer?.invalidate()
            let timer = Timer(
                timeInterval: Self.hoverIntentDelay,
                target: self,
                selector: #selector(showIfStillHovered),
                userInfo: nil,
                repeats: false
            )
            RunLoop.main.add(timer, forMode: .common)
            presentationTimer = timer
        }

        override func mouseExited(with event: NSEvent) {
            isPointerInside = false
            presentationTimer?.invalidate()
            presentationTimer = nil
            hide?(self)
        }

        @objc private func showIfStillHovered() {
            presentationTimer = nil
            guard isPointerInside else { return }
            show?(self)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window == nil else { return }
            isPointerInside = false
            presentationTimer?.invalidate()
            presentationTimer = nil
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
