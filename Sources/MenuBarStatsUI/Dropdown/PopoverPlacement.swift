import AppKit
import SwiftUI

/// Fixes the viewport before presentation and keeps the popover window inside its anchor's display.
@MainActor
enum PopoverPlacement {
    static func configure<Content: View>(_ popover: NSPopover, content: Content, size: NSSize) {
        let controller = NSHostingController(rootView: content)
        // A scroll document's ideal height must never resize the outer popover.
        controller.sizingOptions = []
        controller.view.setFrameSize(size)
        popover.contentViewController = controller
        popover.contentSize = size
    }

    static func constrain(_ popover: NSPopover, to screen: NSScreen?) {
        guard let window = popover.contentViewController?.view.window,
              let screen = screen ?? window.screen else { return }
        let frame = containedFrame(window.frame, in: screen.visibleFrame.insetBy(dx: 8, dy: 8))
        if window.frame != frame { window.setFrame(frame, display: true) }
    }

    static func containedFrame(_ frame: NSRect, in visible: NSRect) -> NSRect {
        let size = NSSize(width: min(frame.width, visible.width), height: min(frame.height, visible.height))
        return NSRect(x: min(max(frame.minX, visible.minX), visible.maxX - size.width),
                      y: min(max(frame.minY, visible.minY), visible.maxY - size.height),
                      width: size.width, height: size.height)
    }
}
