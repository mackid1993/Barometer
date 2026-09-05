import AppKit
import SwiftUI

private struct ShowMenuDetailKey: EnvironmentKey {
    static let defaultValue: @MainActor (AnyView) -> Void = { _ in }
}

extension EnvironmentValues {
    var showMenuDetail: @MainActor (AnyView) -> Void {
        get { self[ShowMenuDetailKey.self] }
        set { self[ShowMenuDetailKey.self] = newValue }
    }
}

/// Ends menu tracking before presenting interactive content in a normal event-processing window.
@MainActor
final class MenuDetailPresenter: NSObject, NSWindowDelegate {
    private(set) var panel: NSPanel?
    private var presentationTimer: Timer?
    private var pendingContent: AnyView?
    private var pendingAnchor = NSPoint.zero
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?

    func show(_ content: AnyView, from menu: NSMenu) {
        close()
        pendingContent = content
        pendingAnchor = NSEvent.mouseLocation
        // Default mode cannot run while AppKit is inside its menu-tracking loop.
        // Task.yield() does not provide that guarantee.
        let timer = Timer(timeInterval: 0, target: self, selector: #selector(finishPresentation),
                          userInfo: nil, repeats: false)
        presentationTimer = timer
        RunLoop.main.add(timer, forMode: .default)
        menu.cancelTracking()
    }

    @objc private func finishPresentation() {
        guard let content = pendingContent else { return }
        let anchor = pendingAnchor
        present(content, at: anchor)
    }

    func present(_ content: AnyView, at anchor: NSPoint) {
        close()
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 900)
        let size = NSSize(width: 380, height: min(640, max(300, visible.height - 100)))
        let window = DetailPanel(contentRect: NSRect(origin: .zero, size: size),
                                 styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.isMovableByWindowBackground = false
        window.animationBehavior = .none
        window.level = .popUpMenu
        window.delegate = self
        window.contentView = NSHostingView(rootView: content.environment(\.closeMenuDetail, { [weak self] in
            self?.close()
        }))
        window.setContentSize(size)
        window.setFrameOrigin(NSPoint(
            x: min(max(visible.minX, anchor.x), visible.maxX - window.frame.width),
            y: min(max(visible.minY, anchor.y - window.frame.height), visible.maxY - window.frame.height)))
        panel = window
        window.makeKeyAndOrderFront(nil)
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] event in
            // AppKit invokes event monitors on the main thread.
            MainActor.assumeIsolated {
                if let self, event.window !== self.panel { self.close() }
            }
            return event
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    func close() {
        presentationTimer?.invalidate()
        presentationTimer = nil
        pendingContent = nil
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        localClickMonitor = nil
        globalClickMonitor = nil
        guard let window = panel else { return }
        panel = nil
        window.delegate = nil
        window.orderOut(nil)
        window.close()
        window.contentView = nil
    }

    // Menu teardown can change key windows after presentation. Dismiss only for an actual
    // outside click, Escape, the close button, or a replacement, not a focus notification.
    func windowWillClose(_ notification: Notification) { close() }
}

private final class DetailPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { close() }
}

private struct CloseMenuDetailKey: EnvironmentKey {
    static let defaultValue: @MainActor () -> Void = {}
}

extension EnvironmentValues {
    var closeMenuDetail: @MainActor () -> Void {
        get { self[CloseMenuDetailKey.self] }
        set { self[CloseMenuDetailKey.self] = newValue }
    }
}
