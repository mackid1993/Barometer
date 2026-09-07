import CoreGraphics
import Foundation

/// The user's configured keyboard shortcut for opening Notification Center.
public struct NotificationCenterShortcut: Equatable, Sendable {
    /// The Unicode character stored by macOS for the shortcut.
    public let character: UInt32

    /// The hardware-independent virtual key code stored by macOS.
    public let keyCode: CGKeyCode

    /// The Core Graphics modifier flags stored by macOS.
    public let modifiers: CGEventFlags

    private static let domain = "com.apple.symbolichotkeys"
    private static let preferenceKey = "AppleSymbolicHotKeys"
    private static let notificationCenterIdentifier = "163"

    /// Reads the enabled Notification Center shortcut from the current user's fresh preferences.
    public static func readConfiguredShortcut() -> NotificationCenterShortcut? {
        CFPreferencesSynchronize(domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard
            let allShortcuts = CFPreferencesCopyValue(
                preferenceKey as CFString,
                domain as CFString,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            ) as? [String: Any],
            let entry = allShortcuts[notificationCenterIdentifier] as? [String: Any],
            (entry["enabled"] as? NSNumber)?.boolValue == true,
            let value = entry["value"] as? [String: Any],
            value["type"] as? String == "standard",
            let parameters = value["parameters"] as? [NSNumber],
            parameters.count >= 3
        else {
            return nil
        }

        let characterValue = parameters[0].int64Value
        let keyCodeValue = parameters[1].int64Value
        let modifierValue = parameters[2].uint64Value
        guard characterValue >= 0, characterValue <= UInt32.max,
              keyCodeValue >= 0, keyCodeValue < 128,
              modifiersAreValid(modifierValue)
        else {
            return nil
        }

        return NotificationCenterShortcut(
            character: UInt32(characterValue),
            keyCode: CGKeyCode(keyCodeValue),
            modifiers: CGEventFlags(rawValue: modifierValue)
        )
    }

    /// Posts one key press using the configured key code and modifiers.
    ///
    /// Accessibility trust must be checked by the UI before calling this method.
    @discardableResult
    public func trigger() async -> Bool {
        guard Self.modifiersAreValid(modifiers.rawValue),
              let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            return false
        }

        keyDown.flags = modifiers
        keyUp.flags = modifiers
        keyDown.post(tap: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(40))
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private static func modifiersAreValid(_ rawValue: UInt64) -> Bool {
        let allowed: CGEventFlags = [
            .maskAlphaShift, .maskShift, .maskControl, .maskAlternate, .maskCommand,
            .maskHelp, .maskSecondaryFn, .maskNumericPad,
        ]
        return rawValue & ~allowed.rawValue == 0
    }
}
