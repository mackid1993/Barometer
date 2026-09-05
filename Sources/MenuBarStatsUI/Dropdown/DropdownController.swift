import AppKit
import OSLog
import SwiftUI

/// Owns a module menu and keeps its hosted SwiftUI content active while menu tracking is running.
///
/// The hosted view is sized to its SwiftUI content every time the menu is about to open and
/// on each tracking tick, so panels never clip. Menus taller than the screen scroll through
/// AppKit's own menu scrolling. Status-item identity and menu attachment are unchanged.
///
/// The hosting view is built on demand. Ten controllers exist from launch, and keeping a
/// SwiftUI hierarchy alive in each one held tens of thousands of attribute graph nodes
/// resident while every panel was closed. The controller keeps only the root view and
/// creates the NSHostingView in menuWillOpen or when the popover opens, then releases it
/// shortly after the panel closes and asks libmalloc to return the freed pages.
///
/// macOS also populates closed menus when accessibility clients such as menu bar managers
/// inspect them, and each of those calls previously forced a full SwiftUI layout pass. The
/// hosted content stays current on its own through the observable stores, so closed menus
/// refresh only through menuWillOpen when a person actually opens the panel.
@MainActor
public final class DropdownController: NSObject, NSMenuDelegate, NSPopoverDelegate {
    private let moduleName: String
    private let tickAction: @MainActor () -> Void
    private let settingsAction: @MainActor () -> Void
    private let quitAction: @MainActor () -> Void
    private let logger = Logger(subsystem: "com.barometer.app", category: "dropdown")
    private let rootView: AnyView
    private let contentHeight: CGFloat
    private var hostingView: NSHostingView<AnyView>?
    private let contentItem = NSMenuItem()
    private var teardownTask: Task<Void, Never>?
    private let contentWidth: CGFloat
    private let menu: NSMenu
    private var trackingTimer: Timer?
    private let detailPresenter = MenuDetailPresenter()
    private weak var detailAnchor: NSView?
    private let usesPopover: Bool
    private var rootPopover: NSPopover?
    private var isTracking = false

    /// Creates and installs a hosted menu for one permanent status item.
    public init(
        moduleName: String,
        statusItem: NSStatusItem?,
        rootView: AnyView,
        contentHeight: CGFloat,
        contentWidth: CGFloat = 320,
        usesPopover: Bool = false,
        tickAction: @escaping @MainActor () -> Void,
        settingsAction: @escaping @MainActor () -> Void,
        quitAction: @escaping @MainActor () -> Void
    ) {
        self.moduleName = moduleName
        self.tickAction = tickAction
        self.settingsAction = settingsAction
        self.quitAction = quitAction
        self.contentWidth = contentWidth
        self.usesPopover = usesPopover
        self.detailAnchor = statusItem?.button
        self.rootView = rootView
        self.contentHeight = contentHeight
        menu = NSMenu()
        super.init()

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

    /// Attaches this controller's permanent menu to a newly enabled status item.
    public func attach(statusItem: NSStatusItem) {
        detailAnchor = statusItem.button
        if usesPopover {
            statusItem.menu = nil
            statusItem.button?.target = self
            statusItem.button?.action = #selector(togglePopover)
        } else {
            statusItem.menu = menu
        }
    }

    @objc private func togglePopover() {
        if let rootPopover, rootPopover.isShown {
            rootPopover.performClose(nil)
            return
        }
        guard let anchor = detailAnchor else { return }
        cancelTeardown()
        tickAction()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        let height = min(720, (anchor.window?.screen?.visibleFrame.height ?? 900) - 100)
        let content = VStack(spacing: 0) {
            wiredRootView()
            Divider()
            HStack {
                Button("Settings…") { [weak self] in
                    self?.rootPopover?.performClose(nil)
                    self?.settingsAction()
                }
                Spacer()
                Button("Quit Barometer") { [weak self] in self?.quitAction() }
            }.padding(12)
        }.frame(width: contentWidth, height: height)
        popover.contentViewController = NSHostingController(rootView: content)
        rootPopover = popover
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        trackingTimer?.invalidate()
        let timer = Timer(timeInterval: 0.5, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        trackingTimer = timer
    }

    public func popoverShouldDetach(_ popover: NSPopover) -> Bool { false }

    public func popoverDidClose(_ notification: Notification) {
        detailPresenter.close()
        trackingTimer?.invalidate()
        trackingTimer = nil
        let closingPopover = rootPopover
        rootPopover = nil
        scheduleTeardown {
            closingPopover?.contentViewController = nil
        }
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        // Accessibility population of a closed menu reaches this delegate before any open
        // sequence, and menuWillOpen performs the tick and fit for a real open anyway. Doing
        // the work here for every inspection made each accessibility poll allocate a full
        // layout pass whose memory the framework keeps.
        guard isTracking else {
            return
        }
        tickAction()
        fitContent()
    }

    public func menuWillOpen(_ menu: NSMenu) {
        detailPresenter.close()
        cancelTeardown()
        installHostingViewIfNeeded()
        isTracking = true
        fitContent()
        trackingTimer?.invalidate()
        let timer = Timer(timeInterval: 0.5, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        trackingTimer = timer
        tick()
        logger.debug("opened module=\(self.moduleName, privacy: .public)")
    }

    public func menuDidClose(_ menu: NSMenu) {
        isTracking = false
        trackingTimer?.invalidate()
        trackingTimer = nil
        scheduleTeardown()
        logger.debug("closed module=\(self.moduleName, privacy: .public)")
    }

    // MARK: - Hosting view lifecycle

    /// The root view with the detail presenter wired into its environment.
    private func wiredRootView() -> AnyView {
        AnyView(
            rootView.environment(
                \.showMenuDetail,
                { [weak self] content, rowAnchor in
                    guard let self else { return }
                    if self.usesPopover {
                        self.detailPresenter.present(content, anchoredTo: rowAnchor, edge: .maxX)
                    } else if let anchor = self.detailAnchor {
                        self.detailPresenter.show(content, from: self.menu, anchoredTo: anchor)
                    }
                }))
    }

    /// Builds the hosting view and installs it into the content item if the menu has none.
    ///
    /// This runs from menuWillOpen, which AppKit sends before the menu is visible, so the view
    /// exists and is fitted by the time the menu draws. Closed-menu accessibility polls never
    /// reach this path and therefore never construct a hierarchy.
    private func installHostingViewIfNeeded() {
        guard !usesPopover, hostingView == nil else { return }
        let view = NSHostingView(rootView: wiredRootView())
        view.sizingOptions = [.intrinsicContentSize]
        view.frame = NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight)
        hostingView = view
        contentItem.view = view
        logger.debug("built hosting view module=\(self.moduleName, privacy: .public)")
    }

    /// Releases the hosted hierarchy once AppKit has finished its close animation.
    ///
    /// The delay is canceled if the panel reopens first. The optional extra step lets popover
    /// mode drop its content view controller in the same pass.
    private func scheduleTeardown(extra: (@MainActor () -> Void)? = nil) {
        teardownTask?.cancel()
        teardownTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(400))
            } catch {
                return
            }
            guard let self else { return }
            self.teardownTask = nil
            self.contentItem.view = nil
            self.hostingView = nil
            extra?()
            MemoryReclaim.scheduleRelief()
            self.logger.debug("released hosting view module=\(self.moduleName, privacy: .public)")
        }
    }

    private func cancelTeardown() {
        teardownTask?.cancel()
        teardownTask = nil
    }

    // MARK: - Sizing

    /// Resizes the hosted view to the ideal height of its SwiftUI content.
    private func fitContent() {
        guard !usesPopover, let hostingView else { return }
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
