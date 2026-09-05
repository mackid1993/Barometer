import AppKit
import SwiftUI

private struct ShowMenuDetailKey: EnvironmentKey {
    static let defaultValue: @MainActor (AnyView, NSView) -> Void = { _, _ in }
}

extension EnvironmentValues {
    var showMenuDetail: @MainActor (AnyView, NSView) -> Void {
        get { self[ShowMenuDetailKey.self] }
        set { self[ShowMenuDetailKey.self] = newValue }
    }
}

/// Presents an attached, non-detachable popover only after AppKit finishes tracking the menu.
@MainActor
final class MenuDetailPresenter: NSObject, NSPopoverDelegate {
    private(set) var popover: NSPopover?
    private var presentationTimer: Timer?
    private var pendingContent: AnyView?
    private weak var pendingAnchor: NSView?
    private weak var hoverAnchor: NSView?
    private var hoverTimer: Timer?
    private var lastHoverTime: TimeInterval = 0
    private let pointerLocation: @MainActor () -> NSPoint

    init(pointerLocation: @escaping @MainActor () -> NSPoint = { NSEvent.mouseLocation }) {
        self.pointerLocation = pointerLocation
        super.init()
    }

    func show(_ content: AnyView, from menu: NSMenu, anchoredTo anchor: NSView) {
        close()
        pendingContent = content
        pendingAnchor = anchor
        // Default mode cannot run while AppKit is inside its menu-tracking loop.
        let timer = Timer(timeInterval: 0, target: self, selector: #selector(finishPresentation),
                          userInfo: nil, repeats: false)
        presentationTimer = timer
        RunLoop.main.add(timer, forMode: .default)
        menu.cancelTracking()
    }

    @objc private func finishPresentation() {
        guard let content = pendingContent, let anchor = pendingAnchor else {
            close()
            return
        }
        present(content, anchoredTo: anchor)
    }

    func present(_ content: AnyView, anchoredTo anchor: NSView, edge: NSRectEdge = .minY) {
        close()
        guard anchor.window != nil else { return }
        let detail = NSPopover()
        detail.behavior = .semitransient
        detail.animates = false
        detail.delegate = self
        let height = min(640, max(300, (anchor.window?.screen?.visibleFrame.height ?? 900) - 100))
        PopoverPlacement.configure(detail, content: content, size: NSSize(width: 380, height: height))
        popover = detail
        detail.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: edge)
        PopoverPlacement.constrain(detail, to: anchor.window?.screen)
        hoverAnchor = anchor
        lastHoverTime = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 0.05, target: self, selector: #selector(checkHover),
                          userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    @objc private func checkHover() {
        updateHover(at: pointerLocation(), time: ProcessInfo.processInfo.systemUptime)
    }

    func updateHover(at point: NSPoint, time: TimeInterval) {
        guard let anchor = hoverAnchor, let anchorWindow = anchor.window,
              let detailWindow = popover?.contentViewController?.view.window else {
            close()
            return
        }
        let row = anchorWindow.convertToScreen(anchor.convert(anchor.visibleRect, to: nil))
        if row.insetBy(dx: -4, dy: -4).contains(point)
            || detailWindow.frame.insetBy(dx: -4, dy: -4).contains(point) {
            lastHoverTime = time
        } else if time - lastHoverTime >= 0.2 {
            // Brief grace permits crossing the gap between the row and its scrollable popover.
            close()
        }
    }

    func close() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        hoverAnchor = nil
        presentationTimer?.invalidate()
        presentationTimer = nil
        pendingContent = nil
        pendingAnchor = nil
        guard let detail = popover else { return }
        popover = nil
        detail.delegate = nil
        detail.close()
        detail.contentViewController = nil
    }

    func popoverShouldDetach(_ popover: NSPopover) -> Bool { false }

    func popoverDidClose(_ notification: Notification) {
        guard let detail = notification.object as? NSPopover, detail === popover else { return }
        close()
    }
}
