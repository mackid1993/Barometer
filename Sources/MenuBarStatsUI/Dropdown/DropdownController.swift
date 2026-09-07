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
    private var hostingView: NSHostingView<AnyView>?
    private let contentHeight: CGFloat
    private let contentWidth: CGFloat
    private let menu: NSMenu
    private let contentItem = NSMenuItem()
    private var trackingTimer: Timer?
    private let detailPresenter = MenuDetailPresenter()
    private let detailActions = MenuDetailActions()
    private weak var detailAnchor: NSView?
    private let usesAttachedPanel: Bool
    private var rootPanel: AttachedPanel?
    private let dismissalMonitor = PopoverDismissalMonitor()
    private var activationHoverRegion: NSRect?
    private var isOpen = false
    private var isMenuTracking = false

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
        self.contentHeight = contentHeight
        self.contentWidth = contentWidth
        self.usesAttachedPanel = usesAttachedPanel
        self.detailAnchor = statusItem?.button
        menu = NSMenu()
        rootContent = rootView
        super.init()

        detailActions.attach(to: self)
        rootContent = AnyView(
            rootView
                .environment(\.menuDetailActions, detailActions)
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuTrackingDidBegin),
            name: NSMenu.didBeginTrackingNotification,
            object: menu
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuTrackingDidEnd),
            name: NSMenu.didEndTrackingNotification,
            object: menu
        )
        menu.delegate = self
        menu.minimumWidth = contentWidth

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

    deinit {
        NotificationCenter.default.removeObserver(self)
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
        presentAttachedPanel(anchoredTo: anchor)
    }

    func presentAttachedPanel(anchoredTo anchor: NSView) {
        detailAnchor = anchor
        becomeActive()
        isOpen = true
        activationHoverRegion = Self.activationHoverRegion(at: NSEvent.mouseLocation, buttonSize: anchor.bounds.size)
        visibilityAction(true)
        let availableHeight = (anchor.window?.screen?.visibleFrame.height ?? 900) - 100
        let height = Self.attachedPanelHeight(contentHeight: contentHeight, availableHeight: availableHeight)
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
    }

    func showMenuDetail(_ content: AnyView, anchoredTo rowAnchor: NSView) {
        if usesAttachedPanel {
            detailPresenter.present(content, anchoredTo: rowAnchor, edge: .maxX)
            if let rootPanel {
                PopoverPlacement.constrain(rootPanel, to: detailAnchor?.window?.screen)
            }
        } else if let detailAnchor {
            detailPresenter.show(content, from: menu, anchoredTo: detailAnchor)
        }
    }

    func hideMenuDetail(anchoredTo rowAnchor: NSView) {
        detailPresenter.anchorDidExit(rowAnchor)
    }

    var hasActiveTrackingTimer: Bool { trackingTimer != nil }
    var hasAllocatedHostingView: Bool { hostingView != nil }
    var representedMenu: NSMenu { menu }

    static func attachedPanelHeight(contentHeight: CGFloat, availableHeight: CGFloat) -> CGFloat {
        min(BarometerDesign.maximumPanelHeight, contentHeight + 56, availableHeight)
    }

    static func activationHoverRegion(at point: NSPoint, buttonSize: NSSize) -> NSRect {
        let size = NSSize(width: max(36, buttonSize.width), height: max(24, buttonSize.height))
        return NSRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                      width: size.width, height: size.height)
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
        activationHoverRegion = nil
        resignActive()
        MemoryReclaim.scheduleRelief()
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        // Accessibility clients populate closed status menus while discovering menu bar items.
        // A real open is prepared in menuWillOpen, so avoid allocating a hidden SwiftUI tree here.
        guard isOpen else { return }
        prepareContent()
        tickAction()
        fitContent()
    }

    public func menuWillOpen(_ menu: NSMenu) {
        // Accessibility clients ask AppKit to simulate opening a closed status menu while they
        // inspect its children. Only real menu tracking posts didBeginTrackingNotification.
        guard isMenuTracking else {
            logger.debug("ignored accessibility menu inspection module=\(self.moduleName, privacy: .public)")
            return
        }
        becomeActive()
        isOpen = true
        activationHoverRegion = Self.activationHoverRegion(
            at: NSEvent.mouseLocation,
            buttonSize: detailAnchor?.bounds.size ?? NSSize(width: 36, height: 24)
        )
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
        guard isOpen else { return }
        finishNativeMenuClose()
    }

    @objc private func menuTrackingDidBegin() {
        isMenuTracking = true
    }

    @objc private func menuTrackingDidEnd() {
        isMenuTracking = false
    }

    private func finishNativeMenuClose() {
        let wasOpen = isOpen
        isOpen = false
        dismissalMonitor.stop()
        if wasOpen { visibilityAction(false) }
        trackingTimer?.invalidate()
        trackingTimer = nil
        contentItem.view = nil
        hostingView?.rootView = AnyView(EmptyView())
        hostingView = nil
        hasHostedContent = false
        activationHoverRegion = nil
        resignActive()
        MemoryReclaim.scheduleRelief()
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

    func dismiss() {
        if usesAttachedPanel {
            closeRootPanel()
        } else {
            menu.cancelTracking()
            finishNativeMenuClose()
        }
    }

    private func prepareContent() {
        guard !hasHostedContent else { return }
        let hostingView = NSHostingView(rootView: rootContent)
        hostingView.sizingOptions = [.intrinsicContentSize]
        hostingView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight)
        self.hostingView = hostingView
        contentItem.view = hostingView
        hasHostedContent = true
    }

    private func startDismissalMonitoring() {
        dismissalMonitor.start(containsPoint: { [weak self] point in
            guard let self else { return false }
            let rootWindow = self.usesAttachedPanel
                ? self.rootPanel : self.hostingView?.window
            return rootWindow?.frame.contains(point) == true
                || self.detailPresenter.panel?.frame.contains(point) == true
                || self.activationHoverRegion?.contains(point) == true
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
        guard !usesAttachedPanel, let hostingView else { return }
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
