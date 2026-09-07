import AppKit
import Foundation
import SystemSources

/// Decides what a click on a listed notification opens.
///
/// Notification Center hands a click to the sending application over a private channel, and the
/// application chooses the destination. Barometer cannot reach that channel, so it reproduces the
/// destinations from what the record itself carries, in this order:
///
/// 1. The notification's own deep link (`durl`), which is where Notification Center goes.
/// 2. A finished download: a file in Downloads or on the Desktop named in the notification text.
/// 3. An absolute path or web link found in the application's user data.
/// 4. System notifications: the System Settings pane or application they belong to.
/// 5. The sending application.
@MainActor
enum NotificationRouter {
    /// Where a notification click goes.
    enum Destination: Equatable {
        case open(URL)
        case revealFile(URL)
        case activateApplication(String)
    }

    /// Folders searched for a file named in the notification, in order.
    static var searchFolders: [URL] {
        let manager = FileManager.default
        return [
            manager.urls(for: .downloadsDirectory, in: .userDomainMask).first,
            manager.urls(for: .desktopDirectory, in: .userDomainMask).first,
        ].compactMap { $0 }
    }

    /// Picks the destination for one notification.
    static func destination(
        for notification: DeliveredNotification,
        folders: [URL] = searchFolders,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> Destination {
        if let deepLink = notification.deepLink, deepLink.scheme != nil {
            return .open(deepLink)
        }
        if let file = downloadedFile(named: [notification.body, notification.subtitle, notification.title], in: folders) {
            return .revealFile(file)
        }
        for hint in notification.hints {
            if hint.hasPrefix("/") {
                if fileExists(hint) { return .revealFile(URL(fileURLWithPath: hint)) }
            } else if let url = URL(string: hint), let scheme = url.scheme, ["http", "https"].contains(scheme) {
                return .open(url)
            }
        }
        if let system = systemDestination(for: notification) {
            return system
        }
        return .activateApplication(notification.applicationIdentifier)
    }

    /// Opens the destination.
    static func open(_ destination: Destination) {
        switch destination {
        case let .open(url):
            NSWorkspace.shared.open(url)
        case let .revealFile(url):
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case let .activateApplication(bundleIdentifier):
            NotificationApplicationResolver.open(bundleIdentifier: bundleIdentifier)
        }
    }

    /// One-line description for a tooltip.
    static func label(for destination: Destination) -> String {
        switch destination {
        case let .open(url):
            if url.scheme == "x-apple.systempreferences" { return "Open System Settings" }
            if url.scheme == "macappstore" { return "Open App Store updates" }
            return "Open \(url.host ?? url.scheme ?? "link")"
        case let .revealFile(url):
            return "Show \(url.lastPathComponent)"
        case let .activateApplication(bundleIdentifier):
            return "Open \(NotificationApplicationResolver.name(bundleIdentifier: bundleIdentifier))"
        }
    }

    // MARK: - System notifications

    /// System Settings panes and applications behind Apple's system notifications.
    static let systemDestinations: [(prefix: String, destination: Destination)] = [
        ("com.apple.appstore", .open(URL(string: "macappstore://showUpdatesPage")!)),
        ("com.apple.softwareupdatenotification",
         .open(URL(string: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension")!)),
        ("com.apple.btusernotifications",
         .open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)),
        ("com.apple.bluetoothuserd", .open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)),
        ("com.apple.controlcenter.notifications.low-battery",
         .open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)),
        ("com.apple.audioaccessory", .open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)),
        ("com.apple.tmhelperagent",
         .open(URL(string: "x-apple.systempreferences:com.apple.Time-Machine-Settings.extension")!)),
        ("com.apple.screentime", .open(URL(string: "x-apple.systempreferences:com.apple.Screen-Time-Settings.extension")!)),
        ("com.apple.wifi.usernotifications", .open(URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension")!)),
        ("com.apple.wifip2pd", .open(URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension")!)),
        ("com.apple.tccd", .open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!)),
        ("com.apple.askpermission", .open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!)),
        ("com.apple.mdmclient", .open(URL(string: "x-apple.systempreferences:com.apple.Profiles-Settings.extension")!)),
        ("com.apple.appleaccount", .open(URL(string: "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings")!)),
        ("com.apple.security.keychain-circle", .open(URL(string: "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings")!)),
        ("com.apple.universalcontrol", .open(URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!)),
        ("com.apple.lockdownmode", .open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!)),
        ("com.apple.followup", .open(URL(string: "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings")!)),
        ("com.apple.sharingd", .open(URL(string: "x-apple.systempreferences:com.apple.General-Settings.extension")!)),
        ("com.apple.passwords", .activateApplication("com.apple.Passwords")),
        ("com.apple.findmy", .activateApplication("com.apple.findmy")),
        ("com.apple.ical", .activateApplication("com.apple.iCal")),
        ("com.apple.reminders", .activateApplication("com.apple.reminders")),
        ("com.apple.facetime", .activateApplication("com.apple.FaceTime")),
        ("com.apple.telephonyutilities", .activateApplication("com.apple.FaceTime")),
        ("com.apple.mobilephone", .activateApplication("com.apple.mobilephone")),
        ("com.apple.shazamnotifications", .activateApplication("com.apple.shazam")),
    ]

    /// The pane or app for a system notification, matched on the identifier without the
    /// `_SYSTEM_CENTER_:` prefix Apple uses for daemon-sent notifications.
    static func systemDestination(for notification: DeliveredNotification) -> Destination? {
        var identifier = notification.applicationIdentifier.lowercased()
        if identifier.hasPrefix("_system_center_:") { identifier.removeFirst("_system_center_:".count) }
        if let category = notification.category?.lowercased(), category.contains("updates-available") {
            return .open(URL(string: "macappstore://showUpdatesPage")!)
        }
        for entry in systemDestinations where identifier.hasPrefix(entry.prefix) {
            return entry.destination
        }
        return nil
    }

    // MARK: - Downloads

    /// The first existing file whose name equals one of the candidate strings.
    ///
    /// Browsers put the file name in the notification body ("Download Complete" / "file.zip"), so an
    /// exact, case-insensitive name match is enough and avoids opening the wrong file.
    static func downloadedFile(named candidates: [String?], in folders: [URL]) -> URL? {
        let names = candidates.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.contains("/") }
        guard !names.isEmpty else { return nil }
        // Always go through the listing so the on-disk spelling wins on case-insensitive volumes.
        for folder in folders {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { continue }
            for entry in entries where names.contains(where: { $0.caseInsensitiveCompare(entry) == .orderedSame }) {
                return folder.appendingPathComponent(entry)
            }
        }
        return nil
    }
}
