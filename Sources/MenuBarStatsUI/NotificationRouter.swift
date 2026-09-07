import AppKit
import Foundation
import SystemSources

/// Routes a click on a listed notification.
///
/// macOS's own notification action is always attempted first. A fallback is allowed only when the
/// native bridge reports that it was unavailable before dispatch, avoiding a second activation
/// after an indeterminate native attempt. Fallbacks use explicit record fields followed by
/// conservative last-resort heuristics, in this order:
///
/// 1. The notification's explicit deep link (`durl`).
/// 2. A finished download: a file in Downloads or on the Desktop named in the notification text.
/// 3. System notifications: the System Settings pane or application they belong to.
/// 4. The sending application.
@MainActor
enum NotificationRouter {
    /// Where a notification click goes.
    enum Destination: Equatable {
        case open(URL)
        case revealFile(URL)
        case activateApplication(String)
    }

    /// Result of routing one click.
    enum Result: Equatable {
        /// macOS accepted the notification's native action.
        case nativeAccepted
        /// The native bridge attempted dispatch but could not confirm acceptance.
        case nativeFailed
        /// Native dispatch was unavailable before attempting it, so Barometer opened this fallback.
        case fallback(Destination)
    }

    /// Injectable native action used to keep routing tests independent of Notification Center.
    typealias NativeAction = @MainActor (DeliveredNotification) async -> NotificationSystemActionResult

    /// Injectable fallback opener used to prevent tests from activating applications.
    typealias DestinationOpener = @MainActor (Destination) -> Void

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
        folders: [URL] = searchFolders
    ) -> Destination {
        if let deepLink = notification.deepLink, deepLink.scheme != nil {
            return .open(deepLink)
        }
        if isBrowserDownload(notification),
           let file = downloadedFile(named: [notification.body, notification.subtitle, notification.title], in: folders)
        {
            return .revealFile(file)
        }
        if let system = systemDestination(for: notification) {
            return system
        }
        return .activateApplication(notification.applicationIdentifier)
    }

    /// Routes through macOS's notification action bridge before considering a fallback.
    @discardableResult
    static func route(_ notification: DeliveredNotification, folders: [URL] = searchFolders) async -> Result {
        await route(
            notification,
            folders: folders,
            nativeAction: { notification in
                await NotificationCenterActionBridge.shared.perform(.activate, for: notification)
            }
        )
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

    /// Attempts the native default action, opening a fallback only when no native dispatch occurred.
    @discardableResult
    static func route(
        _ notification: DeliveredNotification,
        folders: [URL] = searchFolders,
        nativeAction: NativeAction,
        fallbackOpen: DestinationOpener = open
    ) async -> Result {
        switch await nativeAction(notification) {
        case .accepted:
            return .nativeAccepted
        case .failed:
            return .nativeFailed
        case .unavailable:
            let fallback = destination(for: notification, folders: folders)
            fallbackOpen(fallback)
            return .fallback(fallback)
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
    static let systemDestinations: [(prefix: String, destination: Destination)] = systemDestinationURLs.compactMap {
        prefix, value in URL(string: value).map { (prefix, .open($0)) }
    } + [
        ("com.apple.passwords", .activateApplication("com.apple.Passwords")),
        ("com.apple.findmy", .activateApplication("com.apple.findmy")),
        ("com.apple.ical", .activateApplication("com.apple.iCal")),
        ("com.apple.reminders", .activateApplication("com.apple.reminders")),
        ("com.apple.facetime", .activateApplication("com.apple.FaceTime")),
        ("com.apple.telephonyutilities", .activateApplication("com.apple.FaceTime")),
        ("com.apple.mobilephone", .activateApplication("com.apple.mobilephone")),
        ("com.apple.shazamnotifications", .activateApplication("com.apple.shazam")),
    ]

    private static let systemDestinationURLs: [(String, String)] = [
        ("com.apple.appstore", "macappstore://showUpdatesPage"),
        ("com.apple.softwareupdatenotification",
         "x-apple.systempreferences:com.apple.Software-Update-Settings.extension"),
        ("com.apple.btusernotifications", "x-apple.systempreferences:com.apple.BluetoothSettings"),
        ("com.apple.bluetoothuserd", "x-apple.systempreferences:com.apple.BluetoothSettings"),
        ("com.apple.controlcenter.notifications.low-battery",
         "x-apple.systempreferences:com.apple.BluetoothSettings"),
        ("com.apple.audioaccessory", "x-apple.systempreferences:com.apple.BluetoothSettings"),
        ("com.apple.tmhelperagent", "x-apple.systempreferences:com.apple.Time-Machine-Settings.extension"),
        ("com.apple.screentime", "x-apple.systempreferences:com.apple.Screen-Time-Settings.extension"),
        ("com.apple.wifi.usernotifications", "x-apple.systempreferences:com.apple.wifi-settings-extension"),
        ("com.apple.wifip2pd", "x-apple.systempreferences:com.apple.wifi-settings-extension"),
        ("com.apple.tccd", "x-apple.systempreferences:com.apple.preference.security"),
        ("com.apple.askpermission", "x-apple.systempreferences:com.apple.preference.security"),
        ("com.apple.mdmclient", "x-apple.systempreferences:com.apple.Profiles-Settings.extension"),
        ("com.apple.appleaccount", "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings"),
        ("com.apple.security.keychain-circle",
         "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings"),
        ("com.apple.universalcontrol", "x-apple.systempreferences:com.apple.Displays-Settings.extension"),
        ("com.apple.lockdownmode", "x-apple.systempreferences:com.apple.preference.security"),
        ("com.apple.followup", "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings"),
        ("com.apple.sharingd", "x-apple.systempreferences:com.apple.General-Settings.extension"),
    ]

    /// The pane or app for a system notification, matched on the identifier without the
    /// `_SYSTEM_CENTER_:` prefix Apple uses for daemon-sent notifications.
    static func systemDestination(for notification: DeliveredNotification) -> Destination? {
        var identifier = notification.applicationIdentifier.lowercased()
        if identifier.hasPrefix("_system_center_:") { identifier.removeFirst("_system_center_:".count) }
        if let category = notification.category?.lowercased(), category.contains("updates-available") {
            return URL(string: "macappstore://showUpdatesPage").map(Destination.open)
        }
        for entry in systemDestinations where identifier.hasPrefix(entry.prefix) {
            return entry.destination
        }
        return nil
    }

    // MARK: - Downloads

    /// Recognized browser bundle identifiers eligible for the download fallback.
    private static let browserBundleIdentifiers: Set<String> = [
        "com.apple.safari",
        "com.brave.browser",
        "com.google.chrome",
        "com.kagi.kagimacos",
        "com.microsoft.edgemac",
        "com.operasoftware.opera",
        "com.operasoftware.operagx",
        "com.vivaldi.vivaldi",
        "company.thebrowser.browser",
        "org.chromium.chromium",
        "org.mozilla.firefox",
    ]

    /// Whether a browser notification carries explicit download-completion evidence.
    static func isBrowserDownload(_ notification: DeliveredNotification) -> Bool {
        guard browserBundleIdentifiers.contains(notification.applicationIdentifier.lowercased()) else { return false }
        return [notification.title, notification.subtitle, notification.body, notification.category]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains("download") }
    }

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
