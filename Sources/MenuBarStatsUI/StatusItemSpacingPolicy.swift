import Foundation

/// Keeps Barometer's independently movable items compact without changing system-wide spacing.
public enum StatusItemSpacingPolicy {
    static let spacingKey = "NSStatusItemSpacing"
    static let selectionPaddingKey = "NSStatusItemSelectionPadding"

    /// Two points preserves a readable boundary while avoiding the loose AppKit default.
    static let compactValue = 2

    /// Applies the AppKit status-item spacing override before any status item is created.
    public static func apply(to defaults: UserDefaults = .standard) {
        defaults.set(compactValue, forKey: spacingKey)
        defaults.set(compactValue, forKey: selectionPaddingKey)
    }
}
