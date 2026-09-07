import AppKit
import ApplicationServices
import OSLog

/// Opens macOS Notification Center by pressing the system clock through Accessibility.
///
/// macOS has no public API, URL scheme, or default shortcut for Notification Center. The system
/// clock is an `AXMenuBarItem` whose identifier is `com.apple.menuextra.clock`; pressing it toggles
/// Notification Center exactly like a click on the real clock, including the widgets. On macOS 27
/// the item belongs to the Menu Bar Agent process, on earlier releases to Control Center, so both
/// hosts are searched. Every call needs Accessibility access for Barometer and reports failure
/// instead of throwing so the caller can fall back to its own dropdown.
@MainActor
public enum NotificationCenterOpener {
    /// Accessibility identifier of the system clock item.
    static let clockIdentifier = "com.apple.menuextra.clock"

    /// Processes that host the system menu extras, most recent macOS first.
    static let hostBundleIdentifiers = ["com.apple.MenuBarAgent", "com.apple.controlcenter"]

    private static let maximumSearchDepth = 4
    private static let logger = Logger(subsystem: "com.barometer.app", category: "notification-center")

    /// Whether macOS currently lists Barometer as an allowed Accessibility client.
    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Asks macOS to list Barometer under Accessibility, showing the system prompt when it is not yet allowed.
    ///
    /// Call this only from a direct user action, such as turning the setting on.
    @discardableResult
    public static func requestAccess() -> Bool {
        // The header exports the option key as a global `var`, which strict concurrency rejects;
        // its value is the documented string "AXTrustedCheckOptionPrompt".
        return AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Opens the Accessibility pane of System Settings.
    public static func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Toggles Notification Center by pressing the system clock.
    ///
    /// Returns false when Accessibility access is missing or no host exposes the clock item.
    @discardableResult
    public static func toggle() -> Bool {
        guard isTrusted else {
            logger.info("notification center skipped: accessibility access is not allowed")
            return false
        }
        guard let clock = systemClockElement() else {
            logger.error("notification center skipped: the system clock item was not found")
            return false
        }
        let result = AXUIElementPerformAction(clock, kAXPressAction as CFString)
        guard result == .success else {
            logger.error("notification center press failed code=\(result.rawValue, privacy: .public)")
            return false
        }
        logger.debug("notification center toggled")
        return true
    }

    // MARK: - Lookup

    private static func systemClockElement() -> AXUIElement? {
        for bundleIdentifier in hostBundleIdentifiers {
            for host in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier) {
                let application = AXUIElementCreateApplication(host.processIdentifier)
                guard let extras = elementAttribute(kAXExtrasMenuBarAttribute, of: application) else { continue }
                if let clock = element(withIdentifier: clockIdentifier, under: extras, depth: 0) {
                    return clock
                }
            }
        }
        return nil
    }

    private static func element(withIdentifier identifier: String, under root: AXUIElement, depth: Int)
        -> AXUIElement?
    {
        if valueAttribute(kAXIdentifierAttribute, of: root) as? String == identifier {
            return root
        }
        guard depth < maximumSearchDepth,
              let children = valueAttribute(kAXChildrenAttribute, of: root) as? [AXUIElement]
        else {
            return nil
        }
        for child in children {
            if let match = element(withIdentifier: identifier, under: child, depth: depth + 1) {
                return match
            }
        }
        return nil
    }

    private static func elementAttribute(_ name: String, of element: AXUIElement) -> AXUIElement? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value else {
            return nil
        }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func valueAttribute(_ name: String, of element: AXUIElement) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }
}
