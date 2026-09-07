import AppKit
import Foundation
import SystemSources

/// Decides what a click on a listed notification opens.
///
/// Notification Center hands a click to the sending application over a private channel, and the
/// application chooses the destination. Barometer cannot reach that channel, so it reproduces the
/// common destinations itself: a download notification reveals the finished file, and anything else
/// activates the application. The file lookup matches the notification text against the names of
/// files in the user's download folders, which is how browsers title their download notifications.
@MainActor
enum NotificationRouter {
    /// Where a notification click goes.
    enum Destination: Equatable {
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
    static func destination(for notification: DeliveredNotification, folders: [URL] = searchFolders) -> Destination {
        if let file = downloadedFile(named: [notification.body, notification.subtitle, notification.title], in: folders) {
            return .revealFile(file)
        }
        return .activateApplication(notification.applicationIdentifier)
    }

    /// Opens the destination.
    static func open(_ destination: Destination) {
        switch destination {
        case let .revealFile(url):
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case let .activateApplication(bundleIdentifier):
            NotificationApplicationResolver.open(bundleIdentifier: bundleIdentifier)
        }
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
