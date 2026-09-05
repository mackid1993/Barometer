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

/// Presents an attached, non-draggable panel only after AppKit finishes tracking the menu.
@MainActor
final class MenuDetailPresenter: NSObject {
    private(set) var panel: AttachedPanel?
    private var presentationTimer: Timer?
    private var pendingContent: AnyView?
    private weak var pendingAnchor: NSView?
    private weak var hoverAnchor: NSView?
    private var hoverTimer: Timer?
    private let dismissalMonitor = PopoverDismissalMonitor()
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
        guard let anchorWindow = anchor.window else { return }
        let height = min(640, max(300, (anchor.window?.screen?.visibleFrame.height ?? 900) - 100))
        let detail = AttachedPanel(content: content, size: NSSize(width: 380, height: height))
        panel = detail
        let anchorRect = anchorWindow.convertToScreen(anchor.convert(anchor.visibleRect, to: nil))
        detail.show(relativeTo: anchorRect, preferredEdge: edge, on: anchorWindow.screen)
        dismissalMonitor.start(containsPoint: { [weak self] point in
            self?.panel?.frame.contains(point) == true
        }, tracksHover: false, dismiss: { [weak self] in self?.close() })
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
              let detailWindow = panel else {
            close()
            return
        }
        let row = anchorWindow.convertToScreen(anchor.convert(anchor.visibleRect, to: nil))
        if row.insetBy(dx: -4, dy: -4).contains(point)
            || detailWindow.frame.insetBy(dx: -4, dy: -4).contains(point) {
            lastHoverTime = time
        } else if time - lastHoverTime >= PopoverDismissalMonitor.hoverExitDelay {
            // Brief grace permits crossing the gap between the row and its scrollable panel.
            close()
        }
    }

    func close() {
        dismissalMonitor.stop()
        hoverTimer?.invalidate()
        hoverTimer = nil
        hoverAnchor = nil
        presentationTimer?.invalidate()
        presentationTimer = nil
        pendingContent = nil
        pendingAnchor = nil
        guard let detail = panel else { return }
        panel = nil
        detail.releaseAndClose()
    }
}
