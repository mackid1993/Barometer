import AppKit
import ApplicationServices
import OSLog
import SystemSources

/// Opens macOS Notification Center through a hot corner the user assigned to it.
///
/// The panel opens from the clock item or from the Dock. With the clock removed from the bar, the clock
/// press, the Show Notification Center shortcut, and every synthesized form of them do nothing, but the
/// Dock's own triggers still work: the trackpad edge swipe and a hot corner assigned to Notification
/// Center. Verified on macOS 27 with the clock hidden by a menu bar manager: driving the pointer into
/// such a corner with synthesized moves opens the panel.
///
/// Barometer never writes the Dock's preferences and never relaunches the Dock; the corner is assigned
/// once by the user in System Settings. A press hides the cursor, jumps it into the corner, waits for
/// the panel to report open, and puts the cursor back exactly where it was before showing it again, so
/// the pointer is never seen to move.
@MainActor
enum NotificationCenterOpening {
    private static let logger = Logger(subsystem: "com.barometer.app", category: "notification-center")
    private static var isOpening = false

    /// Geometric corners by the Dock's preference key.
    private static func point(for key: String, in display: CGRect) -> CGPoint {
        switch key {
        case "tl": CGPoint(x: display.minX, y: display.minY)
        case "tr": CGPoint(x: display.maxX - 1, y: display.minY)
        case "bl": CGPoint(x: display.minX, y: display.maxY - 1)
        default: CGPoint(x: display.maxX - 1, y: display.maxY - 1)
        }
    }

    /// The Dock preference key of a corner assigned to Notification Center, if any.
    static var assignedCornerKey: String? {
        DockHotCorners.preferenceActions().first { $0.value == Int(DockHotCorners.notificationCenterAction) }?.key
    }

    /// Whether Notification Center's panel is currently open, from the panel process's own expanded state.
    static func isPanelOpen() -> Bool {
        for host in NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui") {
            var value: AnyObject?
            let application = AXUIElementCreateApplication(host.processIdentifier)
            if AXUIElementCopyAttributeValue(application, "AXExpanded" as CFString, &value) == .success,
               let expanded = value as? Bool, expanded
            {
                return true
            }
        }
        return false
    }

    static func open() {
        guard !isOpening else { return }
        isOpening = true
        Task {
            defer { isOpening = false }
            // Let the dropdown dismiss and release its menu event tracking first.
            try? await Task.sleep(for: .milliseconds(250))
            guard let key = assignedCornerKey else {
                logger.notice("no hot corner is assigned to Notification Center; see Time and Notifications settings")
                return
            }
            guard AXIsProcessTrusted() else {
                logger.error("opening notification center needs Accessibility access")
                NotificationAccessSettings.requestAccessibility()
                return
            }
            if isPanelOpen() { return }
            let opened = await fire(point(for: key, in: CGDisplayBounds(CGMainDisplayID())))
            logger.notice("notification center via the \(key, privacy: .public) corner: \(opened ? "opened" : "did not open", privacy: .public)")
        }
    }

    /// Hides the cursor, jumps it into the corner, waits for the panel, and puts it back before showing it.
    private static func fire(_ target: CGPoint) async -> Bool {
        guard let original = CGEvent(source: nil)?.location else { return false }
        let source = CGEventSource(stateID: .hidSystemState)
        let inward = CGPoint(x: target.x < 1 ? 1 : -1, y: target.y < 1 ? 1 : -1)
        let approach = [CGPoint(x: target.x + inward.x * 4, y: target.y + inward.y * 4), target, target]
        CGDisplayHideCursor(CGMainDisplayID())
        defer { CGDisplayShowCursor(CGMainDisplayID()) }
        for point in approach {
            guard let move = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point,
                                     mouseButton: .left)
            else { return false }
            move.post(tap: .cghidEventTap)
            try? await Task.sleep(for: .milliseconds(16))
        }
        var opened = false
        let deadline = ContinuousClock.now + .milliseconds(700)
        while ContinuousClock.now < deadline {
            if isPanelOpen() { opened = true; break }
            try? await Task.sleep(for: .milliseconds(25))
        }
        if let back = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: original,
                              mouseButton: .left)
        {
            back.post(tap: .cghidEventTap)
        }
        return opened
    }

    /// Opens the Desktop & Dock pane, where the corner is assigned.
    static func openHotCornerSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}
