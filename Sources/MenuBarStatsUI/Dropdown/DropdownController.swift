import AppKit
import OSLog
import SwiftUI

/// Owns a module menu and keeps its hosted SwiftUI content active while menu tracking is running.
@MainActor
public final class DropdownController: NSObject, NSMenuDelegate {
    private let moduleName: String
    private let tickAction: @MainActor () -> Void
    private let settingsAction: @MainActor () -> Void
    private let quitAction: @MainActor () -> Void
    private let logger = Logger(subsystem: "net.brustein.MenuBarStats", category: "dropdown")
    private var trackingTimer: Timer?

    /// Creates and installs a 320-point-wide hosted menu for one permanent status item.
    public init(
        moduleName: String,
        statusItem: NSStatusItem,
        rootView: AnyView,
        contentHeight: CGFloat,
        tickAction: @escaping @MainActor () -> Void,
        settingsAction: @escaping @MainActor () -> Void,
        quitAction: @escaping @MainActor () -> Void
    ) {
        self.moduleName = moduleName
        self.tickAction = tickAction
        self.settingsAction = settingsAction
        self.quitAction = quitAction
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        menu.minimumWidth = 320

        let contentItem = NSMenuItem()
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: contentHeight)
        contentItem.view = hostingView
        menu.addItem(contentItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quit MenuBarStats", action: #selector(quitApplication), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    public func menuWillOpen(_ menu: NSMenu) {
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

    @objc private func tick() {
        tickAction()
        logger.debug("tracking tick module=\(self.moduleName, privacy: .public)")
    }

    @objc private func openSettings() {
        settingsAction()
    }

    @objc private func quitApplication() {
        quitAction()
    }
}
