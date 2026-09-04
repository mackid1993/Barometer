import Foundation

/// Keeps Barometer's independently movable items compact without changing system-wide spacing.
public enum StatusItemSpacingPolicy {
    static let spacingKey = "NSStatusItemSpacing"
    static let selectionPaddingKey = "NSStatusItemSelectionPadding"

    /// One point keeps independently movable items dense without allowing their canvases to touch.
    static let compactValue = 1

    /// Applies the AppKit status-item spacing override before any status item is created.
    public static func apply(to defaults: UserDefaults = .standard) {
        defaults.set(compactValue, forKey: spacingKey)
        defaults.set(compactValue, forKey: selectionPaddingKey)
    }
}
