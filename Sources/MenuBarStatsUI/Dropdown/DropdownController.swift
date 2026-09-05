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
    private static weak var activeController: DropdownController?

    private let moduleName: String
    private let visibilityAction: @MainActor (Bool) -> Void
    private let tickAction: @MainActor () -> Void
    private let settingsAction: @MainActor () -> Void
    private let quitAction: @MainActor () -> Void
    private let logger = Logger(subsystem: "com.barometer.app", category: "dropdown")
    private var rootContent: AnyView
    private var hasHostedContent = false
    private let hostingView: NSHostingView<AnyView>
    private let contentWidth: CGFloat
    private let menu: NSMenu
    private var trackingTimer: Timer?
    private let detailPresenter = MenuDetailPresenter()
    private weak var detailAnchor: NSView?
    private let usesAttachedPanel: Bool
    private var rootPanel: AttachedPanel?
    private let dismissalMonitor = PopoverDismissalMonitor()
    private var isOpen = false

    /// Creates and installs a hosted menu for one permanent status item.
    public init(
        moduleName: String,
        statusItem: NSStatusItem?,
        rootView: AnyView,
        contentHeight: CGFloat,
        contentWidth: CGFloat = 320,
        usesAttachedPanel: Bool = false,
        visibilityAction: @escaping @MainActor (Bool) -> Void = { _ in },
        tickAction: @escaping @MainActor () -> Void,
        settingsAction: @escaping @MainActor () -> Void,
        quitAction: @escaping @MainActor () -> Void
    ) {
        self.moduleName = moduleName
        self.visibilityAction = visibilityAction
        self.tickAction = tickAction
        self.settingsAction = settingsAction
        self.quitAction = quitAction
        self.contentWidth = contentWidth
        self.usesAttachedPanel = usesAttachedPanel
        self.detailAnchor = statusItem?.button
        menu = NSMenu()
        rootContent = rootView
        hostingView = NSHostingView(rootView: AnyView(EmptyView()))
        hostingView.sizingOptions = [.intrinsicContentSize]
        hostingView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight)
        super.init()

        rootContent = AnyView(rootView.environment(\.showMenuDetail, { [weak self] content, rowAnchor in
            guard let self else { return }
            if self.usesAttachedPanel {
                self.detailPresenter.present(content, anchoredTo: rowAnchor, edge: .maxX)
                if let root = self.rootPanel {
                    PopoverPlacement.constrain(root, to: self.detailAnchor?.window?.screen)
                }
            } else if let anchor = self.detailAnchor {
                self.detailPresenter.show(content, from: self.menu, anchoredTo: anchor)
            }
        }))
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
        if let statusItem { attach(statusItem: statusItem) }
    }

    /// Attaches this controller's permanent menu to a newly enabled status item.
    public func attach(statusItem: NSStatusItem) {
        detailAnchor = statusItem.button
        if usesAttachedPanel {
            statusItem.menu = nil
            statusItem.button?.target = self
            statusItem.button?.action = #selector(togglePanel)
        } else {
            statusItem.menu = menu
        }
    }

    @objc private func togglePanel() {
        if rootPanel?.isVisible == true {
            closeRootPanel()
            return
        }
        guard let anchor = detailAnchor else { return }
        becomeActive()
        isOpen = true
        visibilityAction(true)
        tickAction()
        let height = min(720, (anchor.window?.screen?.visibleFrame.height ?? 900) - 100)
        let content = VStack(spacing: 0) {
            rootContent
            Divider()
            HStack {
                Button("Settings…") { [weak self] in
                    self?.closeRootPanel()
                    self?.settingsAction()
                }
                Spacer()
                Button("Quit Barometer") { [weak self] in self?.quitAction() }
            }.padding(12)
        }.frame(width: contentWidth, height: height)
        let panel = AttachedPanel(content: AnyView(content), size: NSSize(width: contentWidth, height: height))
        rootPanel = panel
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? anchor.window?.screen
        let point = NSEvent.mouseLocation
        panel.show(relativeTo: NSRect(x: point.x - 1, y: point.y - 1, width: 2, height: 2),
                   preferredEdge: .minY, on: screen)
        startDismissalMonitoring()
        trackingTimer?.invalidate()
        let timer = Timer(timeInterval: 0.5, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        trackingTimer = timer
    }

    private func closeRootPanel() {
        let wasOpen = isOpen
        isOpen = false
        dismissalMonitor.stop()
        if wasOpen { visibilityAction(false) }
        detailPresenter.close()
        trackingTimer?.invalidate()
        trackingTimer = nil
        rootPanel?.releaseAndClose()
        rootPanel = nil
        resignActive()
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        prepareContent()
        tickAction()
        fitContent()
    }

    public func menuWillOpen(_ menu: NSMenu) {
        becomeActive()
        isOpen = true
        prepareContent()
        visibilityAction(true)
        detailPresenter.close()
        fitContent()
        trackingTimer?.invalidate()
        let timer = Timer(timeInterval: 0.5, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        trackingTimer = timer
        tick()
        startDismissalMonitoring()
        logger.debug("opened module=\(self.moduleName, privacy: .public)")
    }

    public func menuDidClose(_ menu: NSMenu) {
        finishNativeMenuClose()
    }

    private func finishNativeMenuClose() {
        let wasOpen = isOpen
        isOpen = false
        dismissalMonitor.stop()
        if wasOpen { visibilityAction(false) }
        trackingTimer?.invalidate()
        trackingTimer = nil
        hostingView.rootView = AnyView(EmptyView())
        hasHostedContent = false
        resignActive()
        logger.debug("closed module=\(self.moduleName, privacy: .public)")
    }

    private func becomeActive() {
        let previous = Self.activeController
        Self.activeController = self
        if let previous, previous !== self {
            previous.dismiss()
        }
    }

    private func resignActive() {
        if Self.activeController === self {
            Self.activeController = nil
        }
    }

    private func dismiss() {
        if usesAttachedPanel {
            closeRootPanel()
        } else {
            menu.cancelTracking()
            finishNativeMenuClose()
        }
    }

    private func prepareContent() {
        guard !hasHostedContent else { return }
        hostingView.rootView = rootContent
        hasHostedContent = true
    }

    private func startDismissalMonitoring() {
        dismissalMonitor.start(containsPoint: { [weak self] point in
            guard let self else { return false }
            let rootWindow = self.usesAttachedPanel
                ? self.rootPanel : self.hostingView.window
            return rootWindow?.frame.contains(point) == true
                || self.detailPresenter.panel?.frame.contains(point) == true
                || self.detailAnchor.map { anchor in
                    anchor.window?.convertToScreen(anchor.convert(anchor.bounds, to: nil)).contains(point) == true
                } == true
        }, dismiss: { [weak self] in
            guard let self else { return }
            self.dismiss()
        })
    }

    /// Resizes the hosted view to the ideal height of its SwiftUI content.
    private func fitContent() {
        guard !usesAttachedPanel else { return }
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
        if let rootPanel { PopoverPlacement.constrain(rootPanel, to: detailAnchor?.window?.screen) }
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
