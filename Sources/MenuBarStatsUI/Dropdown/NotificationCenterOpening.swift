import AppKit
import ApplicationServices
import OSLog
import SystemSources

/// Opens macOS Notification Center through a hot corner.
///
/// The panel opens from the clock item or from the Dock. With the clock removed from the bar, the clock press,
/// the Show Notification Center shortcut, and every synthesized form of them do nothing, and the panel's own
/// process refuses connections from anything without an Apple-private entitlement. What still works is the
/// Dock's own triggers: the trackpad edge swipe, which leaves no event a third party can replay, and a hot
/// corner assigned to Notification Center.
///
/// Barometer sets that corner up itself, so nobody has to visit System Settings. It only ever takes a corner
/// the user has left free, and the user chooses which. macOS stores a modifier alongside a corner's action but
/// does not act on it, so the corner cannot be made to answer only to Barometer: whoever chooses it is choosing
/// a corner their own pointer will trip. A press hides the cursor, jumps it into the corner, waits for the
/// panel to report open, and puts the cursor back exactly where it was before showing it again.
@MainActor
enum NotificationCenterOpening {
    private static let logger = Logger(subsystem: "com.barometer.app", category: "notification-center")
    private static var isOpening = false
    private static var isConfiguring = false

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
    static var assignedCornerKey: String? { DockHotCorners.assignedKey() }

    /// Whether the running Dock still offers the calls Barometer needs to assign a corner itself.
    static var canAssignCorner: Bool { DockHotCorners.isAvailable }

    /// The corner Barometer assigned, so it can offer to give that one back and never the user's own.
    private static let ownedCornerKey = "notificationCenterCornerAssignedByBarometer"

    /// What came of asking Barometer to assign the corner.
    enum SetupResult: Equatable, Sendable {
        /// A corner was already assigned to Notification Center; nothing was changed.
        case alreadyAssignedTo(String)
        /// Barometer took the corner and the restarted Dock reports it.
        case assigned(String)
        /// That corner carries one of the user's own actions. Barometer will not take it away.
        case cornerInUse
        /// The assignment could not be made.
        case failed(String)
    }

    /// The corner the settings picker last offered, so the choice survives a restart of Barometer.
    ///
    /// The top right by default: the top left holds the Apple menu, and a pointer sent into a bottom corner
    /// reveals an auto-hiding Dock.
    static var preferredCorner: String {
        get { UserDefaults.standard.string(forKey: preferredCornerKey) ?? "tr" }
        set { UserDefaults.standard.set(newValue, forKey: preferredCornerKey) }
    }

    private static let preferredCornerKey = "notificationCenterPreferredCorner"

    /// What that corner held before Barometer took it, so giving it back restores it exactly.
    private static let ownedActionKey = "notificationCenterCornerPreviousAction"
    private static let ownedModifierKey = "notificationCenterCornerPreviousModifier"

    /// The corner Barometer took, if it still holds Notification Center.
    static var barometerOwnedCorner: String? {
        guard let owned = UserDefaults.standard.string(forKey: ownedCornerKey) else { return nil }
        return owned == assignedCornerKey ? owned : nil
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

    // MARK: - Opening

    static func open() {
        guard !isOpening else { return }
        isOpening = true
        Task {
            defer { isOpening = false }
            // Let the dropdown dismiss and release its menu event tracking first.
            try? await Task.sleep(for: .milliseconds(250))
            guard AXIsProcessTrusted() else {
                logger.error("opening notification center needs Accessibility access")
                NotificationAccessSettings.requestAccessibility()
                return
            }
            if isPanelOpen() { return }
            guard let key = assignedCornerKey else {
                logger.notice("no corner is assigned to Notification Center")
                return
            }
            let opened = await fire(key, modifier: DockHotCorners.preferenceModifier(for: key))
            let outcome = opened ? "opened" : "did not open"
            logger.notice("notification center via \(key, privacy: .public): \(outcome, privacy: .public)")
        }
    }

    /// Hides the cursor, holds the corner's modifier, jumps into the corner, waits for the panel, and puts the
    /// cursor and the modifiers back before showing it.
    /// Sends the pointer into the corner. This is the shipping press path and nothing else uses it: the
    /// cursor is hidden, travels four points, and the move back is posted before it is shown again. It posts
    /// events and nothing else — a cursor warp moves the pointer hard and makes macOS suppress real mouse
    /// deltas afterwards, which is felt as a jump.
    private static func fire(_ key: String, modifier: Int) async -> Bool {
        let target = point(for: key, in: CGDisplayBounds(CGMainDisplayID()))
        guard let original = CGEvent(source: nil)?.location else { return false }
        let source = CGEventSource(stateID: .hidSystemState)
        let keys = modifierKeys(for: modifier)
        let flags = eventFlags(for: modifier)
        let inward = CGPoint(x: target.x < 1 ? 1 : -1, y: target.y < 1 ? 1 : -1)
        let approach = [CGPoint(x: target.x + inward.x * 4, y: target.y + inward.y * 4), target, target]
        CGDisplayHideCursor(CGMainDisplayID())
        // Every one of these has to happen even when an event cannot be built halfway through: an early return
        // used to leave the modifiers logically held down system-wide and the pointer parked in the corner,
        // where it would be revealed and fire the corner again.
        defer {
            for key in keys.reversed() {
                CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)?.post(tap: .cghidEventTap)
            }
            CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: original,
                    mouseButton: .left)?.post(tap: .cghidEventTap)
            CGDisplayShowCursor(CGMainDisplayID())
        }
        for key in keys {
            CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)?.post(tap: .cghidEventTap)
        }
        for point in approach {
            guard let move = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point,
                                     mouseButton: .left)
            else { return false }
            move.flags = flags
            move.post(tap: .cghidEventTap)
            try? await Task.sleep(for: .milliseconds(16))
        }
        var opened = false
        let deadline = ContinuousClock.now + .milliseconds(700)
        while ContinuousClock.now < deadline {
            if isPanelOpen() { opened = true; break }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return opened
    }

    /// The keys a modifier mask stands for, so the corner sees them genuinely held.
    private static func modifierKeys(for modifier: Int) -> [CGKeyCode] {
        var keys: [CGKeyCode] = []
        if modifier & 131_072 != 0 { keys.append(0x38) }  // shift
        if modifier & 262_144 != 0 { keys.append(0x3B) }  // control
        if modifier & 524_288 != 0 { keys.append(0x3A) }  // option
        if modifier & 1_048_576 != 0 { keys.append(0x37) }  // command
        return keys
    }

    private static func eventFlags(for modifier: Int) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifier & 131_072 != 0 { flags.insert(.maskShift) }
        if modifier & 262_144 != 0 { flags.insert(.maskControl) }
        if modifier & 524_288 != 0 { flags.insert(.maskAlternate) }
        if modifier & 1_048_576 != 0 { flags.insert(.maskCommand) }
        return flags
    }

    // MARK: - Setting the corner up

    // MARK: - Assigning the corner

    /// Gives one corner the user is not using to Notification Center.
    ///
    /// The Dock ignores `CoreDockSetExposeCornerAction` from a third party and does not re-read its corner
    /// assignments on a display reconfiguration, both measured. Writing the preference and restarting the Dock
    /// is what works, so that is what this does, and the caller tells the user before it happens.
    ///
    /// Nothing here moves the pointer: setup assigns the corner and confirms the restarted Dock reports it,
    /// and the user proves it by pressing the button.
    static func configure(corner: String) async -> SetupResult {
        guard !isConfiguring else { return .failed("Setup is already running.") }
        isConfiguring = true
        defer { isConfiguring = false }
        if let existing = assignedCornerKey { return .alreadyAssignedTo(existing) }
        guard DockHotCorners.isFree(corner) else { return .cornerInUse }

        let previousAction = DockHotCorners.storedAction(for: corner)
        let previousModifier = DockHotCorners.storedModifier(for: corner)
        guard DockHotCorners.writePreference(
            corner: corner, action: DockHotCorners.notificationCenterAction, modifier: 0)
        else { return .failed("Barometer could not write the Dock's settings.") }

        guard await restartDockAndWait(reporting: corner) else {
            restore(corner: corner, action: previousAction, modifier: previousModifier)
            return .failed("The Dock did not come back with the corner assigned, so it was put back.")
        }
        UserDefaults.standard.set(corner, forKey: ownedCornerKey)
        UserDefaults.standard.set(Int(previousAction ?? DockHotCorners.unassignedAction), forKey: ownedActionKey)
        UserDefaults.standard.set(Int(previousModifier), forKey: ownedModifierKey)
        logger.notice("assigned the \(corner, privacy: .public) corner to Notification Center")
        return .assigned(corner)
    }

    /// Restarts the Dock and waits for a new one that reports the corner.
    ///
    /// The Dock's process identity is what says the restart happened. Waiting only for the corner would fall
    /// through immediately whenever it was already assigned, before the old Dock had finished quitting.
    private static func restartDockAndWait(reporting corner: String) async -> Bool {
        let before = Set(DockHotCorners.dockProcessIdentifiers())
        DockHotCorners.restartDock()
        let restarted = ContinuousClock.now + .seconds(25)
        while ContinuousClock.now < restarted {
            let now = Set(DockHotCorners.dockProcessIdentifiers())
            if !now.isEmpty, now.isDisjoint(with: before) { break }
            try? await Task.sleep(for: .milliseconds(150))
        }
        // A separate deadline: a Dock that took the whole first budget to come back would otherwise leave no
        // time at all to answer, and setup would put a good assignment back and report a failure.
        let reported = ContinuousClock.now + .seconds(15)
        while ContinuousClock.now < reported {
            if assignedCornerKey == corner { return true }
            try? await Task.sleep(for: .milliseconds(150))
        }
        return false
    }

    @discardableResult
    private static func restore(corner: String, action: Int32?, modifier: Int32) -> Bool {
        let written = DockHotCorners.writePreference(
            corner: corner, action: action ?? DockHotCorners.unassignedAction, modifier: modifier)
        DockHotCorners.restartDock()
        return written
    }

    /// Gives back the corner Barometer assigned, exactly as it found it. A corner the user set is untouched.
    static func releaseCorner() {
        guard let corner = barometerOwnedCorner else { return }
        let action = Int32(UserDefaults.standard.integer(forKey: ownedActionKey))
        // Forgetting the corner before it is actually back would strand it: the button that gives it back
        // only appears while Barometer still knows it owns one.
        guard restore(
            corner: corner, action: action == 0 ? DockHotCorners.unassignedAction : action,
            modifier: Int32(UserDefaults.standard.integer(forKey: ownedModifierKey)))
        else {
            logger.error("could not write the corner back; keeping the record so it can be tried again")
            return
        }
        for key in [ownedCornerKey, ownedActionKey, ownedModifierKey] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// Opens the Desktop & Dock pane, where a corner can also be assigned by hand.
    static func openHotCornerSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}
