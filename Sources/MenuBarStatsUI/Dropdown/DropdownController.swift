import AppKit
import OSLog
import SwiftUI

/// Owns a module menu and keeps its hosted SwiftUI content active while menu tracking is running.
///
/// The hosted view is sized to its SwiftUI content every time the menu is about to open and
/// on each tracking tick, so panels never clip. Menus taller than the screen scroll through
/// AppKit's own menu scrolling. Status-item identity and menu attachment are unchanged.
@MainActor
public final class DropdownController: NSObject, NSMenuDelegate {
    private let moduleName: String
    private let tickAction: @MainActor () -> Void
    private let settingsAction: @MainActor () -> Void
    private let quitAction: @MainActor () -> Void
    private let logger = Logger(subsystem: "com.barometer.app", category: "dropdown")
    private let hostingView: NSHostingView<AnyView>
    private let contentWidth: CGFloat
    private var trackingTimer: Timer?

    /// Creates and installs a hosted menu for one permanent status item.
    public init(
        moduleName: String,
        statusItem: NSStatusItem,
        rootView: AnyView,
        contentHeight: CGFloat,
        contentWidth: CGFloat = 320,
        tickAction: @escaping @MainActor () -> Void,
        settingsAction: @escaping @MainActor () -> Void,
        quitAction: @escaping @MainActor () -> Void
    ) {
        self.moduleName = moduleName
        self.tickAction = tickAction
        self.settingsAction = settingsAction
        self.quitAction = quitAction
        self.contentWidth = contentWidth
        hostingView = NSHostingView(rootView: rootView)
        hostingView.sizingOptions = [.intrinsicContentSize]
        hostingView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight)
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        menu.minimumWidth = contentWidth

        let contentItem = NSMenuItem()
        contentItem.view = hostingView
        menu.addItem(contentItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quit Barometer", action: #selector(quitApplication), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        tickAction()
        fitContent()
    }

    public func menuWillOpen(_ menu: NSMenu) {
        fitContent()
        trackingTimer?.invalidate()
        let timer = Timer(timeInterval: 0.5, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        trackingTimer = timer
        tick()
        logger.debug("opened module=\(self.moduleName, privacy: .public)")
    }

    public func menuDidClose(_ menu: NSMenu) {
        trackingTimer?.invalidate()
        trackingTimer = nil
        logger.debug("closed module=\(self.moduleName, privacy: .public)")
    }

    /// Resizes the hosted view to the ideal height of its SwiftUI content.
    private func fitContent() {
        let maximumHeight = min(BarometerDesign.maximumPanelHeight, (NSScreen.main?.visibleFrame.height ?? 900) - 120)
        var measured = hostingView.intrinsicContentSize.height
        if !measured.isFinite || measured <= 0 {
            measured = hostingView.fittingSize.height
        }
        guard measured.isFinite, measured > 0 else {
            return
        }
        let height = min(maximumHeight, max(80, ceil(measured)))
        if abs(hostingView.frame.height - height) > 0.5 || abs(hostingView.frame.width - contentWidth) > 0.5 {
            hostingView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: height)
            logger.debug("fit module=\(self.moduleName, privacy: .public) height=\(height, privacy: .public)")
        }
    }

    @objc private func tick() {
        tickAction()
        fitContent()
        logger.debug("tracking tick module=\(self.moduleName, privacy: .public)")
    }

    @objc private func openSettings() {
        settingsAction()
    }

    @objc private func quitApplication() {
        quitAction()
    }
}
