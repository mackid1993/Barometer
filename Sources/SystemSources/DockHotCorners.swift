import AppKit
import ApplicationServices
import Darwin
import Foundation

/// Reads and assigns the Dock's hot corner actions.
///
/// System Settings writes a corner's action into the Dock's preferences, but the running Dock never observes
/// that write: it posts `com.apple.dock.hotcorner.updated` and subscribes to nothing, so a preference change
/// only takes effect when the Dock next starts. The live path is CoreDock's Mach remote call into the running
/// Dock, which applies at once. Both are used here: the remote call first, the preference write and a Dock
/// restart offered only if the remote call does not take.
///
/// Barometer assigns a corner only when the user has one free, and never changes one the user has assigned.
/// macOS stores a modifier alongside a corner's action but does not act on it: the corner fires whenever the
/// pointer reaches it, so an assigned corner belongs to the user's pointer as much as to Barometer.
public enum DockHotCorners {
    /// The Dock's action value for a corner assigned to Notification Center.
    public static let notificationCenterAction: Int32 = 12

    /// The Dock's action value for a corner that does nothing. Absent and `0` mean the same thing.
    public static let unassignedAction: Int32 = 1

    /// The Dock's preference keys, in the order `CoreDockGetExposeCornerActions` reports them.
    public static let cornerKeys = ["tl", "tr", "bl", "br"]

    /// Corners in the order Barometer would rather use: the top right first, then the bottom two, with the
    /// top left last because it holds the Apple menu.
    public static let borrowOrder = ["tr", "br", "bl", "tl"]

    // MARK: - Preferences

    /// The action assigned to each geometric corner, keyed by the Dock's preference key.
    public static func preferenceActions() -> [String: Int] {
        guard let dock = UserDefaults(suiteName: "com.apple.dock") else { return [:] }
        var result: [String: Int] = [:]
        for key in cornerKeys {
            result[key] = dock.integer(forKey: "wvous-\(key)-corner")
        }
        return result
    }

    /// The modifier a corner asks for, in NSEvent's modifier flags. Zero means the corner needs none.
    public static func preferenceModifier(for key: String) -> Int {
        UserDefaults(suiteName: "com.apple.dock")?.integer(forKey: "wvous-\(key)-modifier") ?? 0
    }

    // MARK: - The live Dock

    nonisolated(unsafe) private static let hiServices: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices",
        RTLD_LAZY)

    private typealias GetActions = @convention(c) (UnsafeMutablePointer<Int32>) -> Void
    private typealias SetActionWithModifier = @convention(c) (Int32, Int32, Int32) -> Void

    private static let getActions: GetActions? = dlsym(hiServices, "CoreDockGetExposeCornerActions")
        .map { unsafeBitCast($0, to: GetActions.self) }
    private static let setActionWithModifier: SetActionWithModifier? =
        dlsym(hiServices, "CoreDockSetExposeCornerActionWithModifier")
        .map { unsafeBitCast($0, to: SetActionWithModifier.self) }

    /// Whether this build of macOS still offers the live corner calls.
    public static var isAvailable: Bool { getActions != nil && setActionWithModifier != nil }

    /// The action the running Dock currently holds for each corner, keyed by preference key.
    ///
    /// The Dock reports an unassigned corner as `1` whether its preference is absent, `0`, or `1`.
    public static func liveActions() -> [String: Int32]? {
        guard let getActions else { return nil }
        // The call fills four integers through one pointer; the buffer is larger so no argument shape can
        // write past what this process owns.
        let buffer = UnsafeMutablePointer<Int32>.allocate(capacity: 16)
        defer { buffer.deallocate() }
        buffer.initialize(repeating: -1, count: 16)
        getActions(buffer)
        var result: [String: Int32] = [:]
        for (index, key) in cornerKeys.enumerated() { result[key] = buffer[index] }
        return result
    }

    /// Asks the running Dock to give one corner an action, and a modifier the pointer must carry to fire it.
    ///
    /// Returns the preference key the assignment landed on, read back from the Dock, or nil when it did not
    /// take. The corner index the call wants is not the order the getter reports, so the landing corner is
    /// always read back rather than assumed.
    @discardableResult
    public static func assign(cornerIndex: Int32, action: Int32, modifier: Int32) -> String? {
        guard let setActionWithModifier else { return nil }
        setActionWithModifier(cornerIndex, action, modifier)
        guard let live = liveActions() else { return nil }
        return cornerKeys.first { live[$0] == action }
    }

    // MARK: - Choosing a corner

    /// The corner already assigned to Notification Center, from the running Dock, falling back to preferences.
    public static func assignedKey() -> String? {
        if let live = liveActions() {
            return cornerKeys.first { live[$0] == notificationCenterAction }
        }
        return preferenceActions().first { $0.value == Int(notificationCenterAction) }?.key
    }

    /// Whether a corner is free: the user has given it no action, in the live Dock and in its preferences.
    public static func isFree(_ key: String) -> Bool {
        let preference = preferenceActions()[key] ?? 0
        guard preference == 0 || preference == Int(unassignedAction) else { return false }
        guard let live = liveActions() else { return true }
        return live[key] == unassignedAction
    }

    // MARK: - The preference route

    private static var dockIdentifier: CFString { "com.apple.dock" as CFString }

    /// Writes a corner's action and its modifier requirement into the Dock's preferences.
    ///
    /// The running Dock does not notice this by itself: it re-reads these keys from `_initialize`, which runs
    /// at launch and from its display reconfiguration handler. `reloadThroughDisplayReconfiguration()` is what
    /// makes a write take effect without restarting anything.
    @discardableResult
    public static func writePreference(corner key: String, action: Int32, modifier: Int32) -> Bool {
        guard cornerKeys.contains(key) else { return false }
        CFPreferencesSetValue(
            "wvous-\(key)-corner" as CFString, action as CFNumber, dockIdentifier,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSetValue(
            "wvous-\(key)-modifier" as CFString, modifier as CFNumber, dockIdentifier,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesAppSynchronize(dockIdentifier)
        return storedAction(for: key) == action
    }

    /// The action stored in the Dock's preferences, read past any cached copy.
    public static func storedAction(for key: String) -> Int32? {
        let value = CFPreferencesCopyValue(
            "wvous-\(key)-corner" as CFString, dockIdentifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return (value as? NSNumber)?.int32Value
    }

    /// The modifier stored in the Dock's preferences, read past any cached copy.
    public static func storedModifier(for key: String) -> Int32 {
        let value = CFPreferencesCopyValue(
            "wvous-\(key)-modifier" as CFString, dockIdentifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return (value as? NSNumber)?.int32Value ?? 0
    }

    /// Makes the running Dock re-read its corner assignments without restarting.
    ///
    /// The Dock re-reads the `wvous-*` keys from `_initialize`, which runs at launch and from its display
    /// reconfiguration handler and nowhere else. An empty display configuration is the cheapest way to reach
    /// the second one: it changes no mode and no arrangement, it only completes a reconfiguration.
    @discardableResult
    public static func reloadThroughDisplayReconfiguration() -> Bool {
        var configuration: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&configuration) == .success, let configuration else { return false }
        return CGCompleteDisplayConfiguration(configuration, .permanently) == .success
    }

    /// Asks the Dock to quit. launchd starts it again at once, and the new Dock reads the corner assignments.
    /// This is the only way a corner assignment written by a third party takes effect: the Dock re-reads the
    /// keys from `_initialize`, and a display reconfiguration was measured not to reach it.
    public static func restartDock() {
        for dock in NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock") {
            dock.terminate()
        }
    }

    /// The Dock processes currently running, so a restart can be told apart from a Dock that never left.
    public static func dockProcessIdentifiers() -> [pid_t] {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").map(\.processIdentifier)
    }

    /// A corner the user has left free, as the index `assign` wants, or nil when every corner is in use.
    ///
    /// The index order the Dock wants is not the order corners are reported in, so every index is offered in
    /// turn and the caller confirms where the assignment landed.
    public static func freeCornerIndexes() -> [Int32] {
        guard borrowOrder.contains(where: isFree) else { return [] }
        return [0, 1, 2, 3]
    }
}
