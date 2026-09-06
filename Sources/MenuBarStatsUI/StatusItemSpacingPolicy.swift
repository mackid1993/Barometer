import Foundation
import MenuBarStatsCore

/// Applies Barometer's own AppKit status-item spacing before any status item is created.
///
/// AppKit reads `NSStatusItemSpacing` and `NSStatusItemSelectionPadding` from the defaults search
/// list and wraps every status item in that much reserved width. Writing them in Barometer's
/// application domain narrows the shell around each item's own immutable length, so it changes the
/// visible gap without ever assigning `statusItem.length` a second time.
///
/// `UserDefaults.standard` writes only Barometer's application domain. It never alters the user's
/// by-host global settings or another application's preferences.
public enum StatusItemSpacingPolicy {
    static let spacingKey = "NSStatusItemSpacing"
    static let selectionPaddingKey = "NSStatusItemSelectionPadding"

    /// Writes or removes Barometer's spacing override for the selected preference.
    ///
    /// Must run before `StatusItemRegistry` is constructed: AppKit reads these values when it
    /// creates each status item window, so a later change cannot move a live item.
    public static func apply(_ spacing: StatusItemSpacing, in defaults: UserDefaults = .standard) {
        guard let points = spacing.points else {
            restoreSystemDefault(in: defaults)
            return
        }
        defaults.set(points, forKey: spacingKey)
        defaults.set(points, forKey: selectionPaddingKey)
    }

    /// Restores AppKit's normal spacing behavior by removing Barometer's application-domain values.
    public static func restoreSystemDefault(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: spacingKey)
        defaults.removeObject(forKey: selectionPaddingKey)
    }
}
