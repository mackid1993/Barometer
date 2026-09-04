import Foundation

/// Removes spacing overrides written by earlier Barometer builds.
public enum StatusItemSpacingPolicy {
    static let spacingKey = "NSStatusItemSpacing"
    static let selectionPaddingKey = "NSStatusItemSelectionPadding"

    /// Restores AppKit's normal spacing behavior before any status item is created.
    ///
    /// `UserDefaults.standard` removes values only from Barometer's application domain. It does not alter the
    /// user's by-host global settings or another application's preferences.
    public static func restoreSystemDefault(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: spacingKey)
        defaults.removeObject(forKey: selectionPaddingKey)
    }
}
