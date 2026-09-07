import Foundation

/// Reads the Dock's hot corner assignments from its preferences.
///
/// System Settings writes a corner's action here when the user assigns it, and the Dock applies it at
/// once. Barometer only reads: it never writes these preferences and never relaunches the Dock.
public enum DockHotCorners {
    /// The Dock's action value for a corner assigned to Notification Center.
    public static let notificationCenterAction: Int32 = 12

    /// The action assigned to each geometric corner, keyed by the Dock's preference key.
    public static func preferenceActions() -> [String: Int] {
        guard let dock = UserDefaults(suiteName: "com.apple.dock") else { return [:] }
        var result: [String: Int] = [:]
        for key in ["tl", "tr", "bl", "br"] {
            result[key] = dock.integer(forKey: "wvous-\(key)-corner")
        }
        return result
    }
}
