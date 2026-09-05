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
    private var pendingPresentation: Task<Void, Never>?

    func show(_ content: AnyView, from menu: NSMenu) {
        close()
        let anchor = NSEvent.mouseLocation
        menu.cancelTracking()
        pendingPresentation = Task { @MainActor [weak self] in
            // Let AppKit tear down the menu and its shadow before creating another window.
            await Task.yield()
            guard !Task.isCancelled else { return }
            self?.present(content, at: anchor)
        }
    }

    func present(_ content: AnyView, at anchor: NSPoint) {
        close()
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 900)
        let size = NSSize(width: 380, height: min(640, max(300, visible.height - 100)))
        let window = DetailPanel(contentRect: NSRect(origin: .zero, size: size),
                                 styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
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
    }

    func close() {
        pendingPresentation?.cancel()
        pendingPresentation = nil
        guard let window = panel else { return }
        panel = nil
        window.delegate = nil
        window.orderOut(nil)
        window.close()
        window.contentView = nil
    }

    func windowDidResignKey(_ notification: Notification) { close() }
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
