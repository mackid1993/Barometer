import AppKit
import ApplicationServices
import OSLog
import SystemSources

/// Opens the native panel through the shortcut the user configured in macOS.
@MainActor
enum NotificationCenterOpening {
    private static var isOpening = false

    static func open() {
        guard !isOpening else { return }
        isOpening = true
        Task {
            defer { isOpening = false }
            // Let the dropdown dismiss and release its menu event tracking before sending keys.
            try? await Task.sleep(for: .milliseconds(250))
            guard let shortcut = NotificationCenterShortcut.readConfiguredShortcut() else {
                showSetup()
                return
            }
            guard AXIsProcessTrusted() else {
                let alert = NSAlert()
                alert.messageText = "Allow Barometer to use your shortcut"
                alert.informativeText = "Enable Barometer in System Settings > Privacy & Security > Accessibility, "
                    + "then click Open Notification Center again."
                alert.addButton(withTitle: "Open Accessibility Settings")
                alert.addButton(withTitle: "Cancel")
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() == .alertFirstButtonReturn {
                    NotificationAccessSettings.requestAccessibility()
                }
                return
            }
            let modifiers: [(CGEventFlags, String)] = [
                (.maskControl, "control down"), (.maskShift, "shift down"),
                (.maskAlternate, "option down"), (.maskCommand, "command down"),
            ]
            let keys = modifiers.filter { shortcut.modifiers.contains($0.0) }.map(\.1)
            let using = keys.isEmpty ? "" : " using {" + keys.joined(separator: ", ") + "}"
            let source = "tell application id \"com.apple.systemevents\" to key code \(shortcut.keyCode)" + using
            var error: NSDictionary?
            guard let script = NSAppleScript(source: source) else { return }
            script.executeAndReturnError(&error)
            if let error {
                let alert = NSAlert()
                alert.messageText = "Could not send your shortcut"
                let number = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
                Logger(subsystem: "com.barometer.app", category: "NotificationCenter").error(
                    "System Events could not send the Notification Center shortcut: \(number)"
                )
                alert.informativeText = "Allow Barometer to control System Events in System Settings > "
                    + "Privacy & Security > Automation, and enable Barometer under Accessibility. "
                    + "Then click Open Notification Center again. (Error \(number))"
                alert.addButton(withTitle: "OK")
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        }
    }

    private static func showSetup() {
        let alert = NSAlert()
        alert.messageText = "Set a Notification Center shortcut"
        alert.informativeText = "In System Settings, open Keyboard > Keyboard Shortcuts > Mission Control. "
            + "Enable Show Notification Center and assign a shortcut, such as Control–Option–N. "
            + "Click Done, check that the shortcut opens Notification Center, then return to Barometer "
            + "and click Open Notification Center again. Barometer will automatically use your shortcut."
        alert.addButton(withTitle: "Open Keyboard Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn,
              let url = URL(string: "x-apple.systempreferences:com.apple.preference.keyboard")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
