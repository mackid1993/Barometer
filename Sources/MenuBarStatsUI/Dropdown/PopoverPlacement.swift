import AppKit

/// Keeps an attached panel inside its anchor's display.
@MainActor
enum PopoverPlacement {
    static func constrain(_ window: NSWindow, to screen: NSScreen?) {
        guard let screen = screen ?? window.screen else { return }
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
