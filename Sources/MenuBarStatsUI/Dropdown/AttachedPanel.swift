import AppKit
import SwiftUI

/// A fixed, non-draggable panel that presents rich SwiftUI content without NSPopover's large backing allocation.
@MainActor
final class AttachedPanel: NSPanel {
    private var hostedView: NSHostingView<AnyView>?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(content: AnyView, size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        isFloatingPanel = true
        isMovable = false
        isMovableByWindowBackground = false
        becomesKeyOnlyIfNeeded = true
        acceptsMouseMovedEvents = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]

        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let surface = AnyView(
            content
                .background(.regularMaterial)
                .clipShape(shape)
                .overlay(shape.stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
        )
        let host = NSHostingView(rootView: surface)
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: size)
        hostedView = host
        contentView = host
    }

    func show(relativeTo anchor: NSRect, preferredEdge: NSRectEdge, on screen: NSScreen?) {
        let gap: CGFloat = 8
        let proposedOrigin: NSPoint
        switch preferredEdge {
        case .maxX:
            proposedOrigin = NSPoint(x: anchor.maxX + gap, y: anchor.maxY - frame.height)
        case .minX:
            proposedOrigin = NSPoint(x: anchor.minX - frame.width - gap, y: anchor.maxY - frame.height)
        case .maxY:
            proposedOrigin = NSPoint(x: anchor.midX - frame.width / 2, y: anchor.maxY + gap)
        default:
            proposedOrigin = NSPoint(x: anchor.midX - frame.width / 2, y: anchor.minY - frame.height - gap)
        }
        let visible = (screen ?? NSScreen.main)?.visibleFrame.insetBy(dx: 8, dy: 8)
            ?? NSRect(origin: proposedOrigin, size: frame.size)
        var proposed = NSRect(origin: proposedOrigin, size: frame.size)
        if preferredEdge == .maxX, proposed.maxX > visible.maxX {
            proposed.origin.x = anchor.minX - proposed.width - gap
        } else if preferredEdge == .minX, proposed.minX < visible.minX {
            proposed.origin.x = anchor.maxX + gap
        }
        setFrame(PopoverPlacement.containedFrame(proposed, in: visible), display: false)
        orderFrontRegardless()
    }

    func releaseAndClose() {
        orderOut(nil)
        contentView = nil
        hostedView = nil
        close()
    }
}
