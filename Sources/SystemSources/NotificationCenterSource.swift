import Foundation
import OSLog
import SQLite3

/// Whether the Notification Center list can be read.
public enum NotificationAccessState: String, Equatable, Sendable {
    /// The list was read.
    case available
    /// The database exists but macOS refused to open it; Full Disk Access is missing.
    case fullDiskAccessRequired
    /// This Mac has no Notification Center database.
    case unavailable
}

/// One notification waiting in Notification Center.
public struct DeliveredNotification: Equatable, Sendable, Identifiable {
    public let id: String
    public let applicationIdentifier: String
    public let title: String
    public let subtitle: String?
    public let body: String?
    public let date: Date

    /// The destination Notification Center itself opens for a click, when the application supplied
    /// one (Apple's apps do: Messages stores a `messages://` link to the conversation).
    public let deepLink: URL?

    /// The application's notification category, such as App Store's updates category.
    public let category: String?

    /// URLs and absolute paths found in the application's user data, most useful first.
    public let hints: [String]

    /// Creates one delivered notification.
    public init(
        id: String,
        applicationIdentifier: String,
        title: String,
        subtitle: String?,
        body: String?,
        date: Date,
        deepLink: URL? = nil,
        category: String? = nil,
        hints: [String] = []
    ) {
        self.id = id
        self.applicationIdentifier = applicationIdentifier
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.date = date
        self.deepLink = deepLink
        self.category = category
        self.hints = hints
    }
}

/// The Notification Center list plus how the read went.
public struct NotificationSnapshot: Equatable, Sendable {
    public let access: NotificationAccessState
    public let notifications: [DeliveredNotification]
    public let readDate: Date

    /// Creates one snapshot.
    public init(access: NotificationAccessState, notifications: [DeliveredNotification], readDate: Date = Date()) {
        self.access = access
        self.notifications = notifications
        self.readDate = readDate
    }
}

/// Reads the notifications waiting in macOS Notification Center.
///
/// macOS has no API for another application's delivered notifications. Notification Center keeps
/// them in an SQLite database under the user notification group container, readable only with
/// Full Disk Access. Each `record` row carries a binary property list with the request's title,
/// subtitle, and body; the `delivered` table lists, per application, the record UUIDs that are
/// still shown in Notification Center. Everything here is read-only: Barometer never writes to,
/// clears, or dismisses anything, and banners keep arriving exactly as before.
public actor NotificationCenterSource {
    /// The database Notification Center maintains on this account.
    public static let defaultDatabaseURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db")

    /// Per-application notification settings, in the same group container.
    ///
    /// Each `apps` entry carries the bundle identifier and a `flags` mask. Bit 25 is set exactly
    /// when the user leaves "Allow notifications" on for that application, and clear when they turn
    /// it off. Notification Center keeps an off application's old records in the database but no
    /// longer shows them, so the list drops them too. The `auth` field is not a reliable signal:
    /// an application the user silenced can still hold a nonzero `auth` (Messages does).
    public static let defaultPreferencesURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(
            "Library/Group Containers/group.com.apple.usernoted/Library/Preferences/group.com.apple.usernoted.plist"
        )

    private let databaseURL: URL
    private let preferencesURL: URL?
    private let logger = Logger(subsystem: "com.barometer.app", category: "notifications")

    /// Creates a source for the given database and settings file, the real ones by default.
    public init(
        databaseURL: URL = NotificationCenterSource.defaultDatabaseURL,
        preferencesURL: URL? = NotificationCenterSource.defaultPreferencesURL
    ) {
        self.databaseURL = databaseURL
        self.preferencesURL = preferencesURL
    }

    /// Whether this account has a Notification Center database at all.
    public var isAvailable: Bool {
        FileManager.default.fileExists(atPath: databaseURL.path)
    }

    /// Files whose changes mean the list may have changed.
    public var watchedURLs: [URL] {
        [databaseURL, URL(fileURLWithPath: databaseURL.path + "-wal"), databaseURL.deletingLastPathComponent()]
    }

    /// Reports access without reading the list, for Settings.
    public static func accessState(databaseURL: URL = defaultDatabaseURL) -> NotificationAccessState {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return .unavailable }
        let descriptor = open(databaseURL.path, O_RDONLY)
        guard descriptor >= 0 else {
            return errno == EPERM || errno == EACCES ? .fullDiskAccessRequired : .unavailable
        }
        close(descriptor)
        return .available
    }

    /// Reads the notifications still shown in Notification Center, newest first.
    public func read(limit: Int = 100) -> NotificationSnapshot {
        let access = Self.accessState(databaseURL: databaseURL)
        guard access == .available else { return NotificationSnapshot(access: access, notifications: []) }

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(databaseURL.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "no handle"
            logger.error("notification database open failed: \(message, privacy: .public)")
            if let handle { sqlite3_close(handle) }
            return NotificationSnapshot(access: .fullDiskAccessRequired, notifications: [])
        }
        defer { sqlite3_close(handle) }

        let shown = deliveredIdentifiers(handle)
        let silenced = Self.silencedApplications(preferencesURL: preferencesURL)
        var notifications: [DeliveredNotification] = []
        let sql = """
            SELECT record.uuid, record.data, record.delivered_date, app.identifier
            FROM record JOIN app ON app.app_id = record.app_id
            WHERE record.delivered_date IS NOT NULL
            ORDER BY record.delivered_date DESC
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            logger.error("notification query failed: \(String(cString: sqlite3_errmsg(handle)), privacy: .public)")
            return NotificationSnapshot(access: .available, notifications: [])
        }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW, notifications.count < limit {
            guard let uuid = Self.blob(statement, column: 0), shown.contains(uuid) else { continue }
            let deliveredDate = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 2))
            let fallbackApplication = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
            guard let data = Self.blob(statement, column: 1),
                  let notification = Self.notification(
                      id: uuid.map { String(format: "%02X", $0) }.joined(),
                      data: data,
                      deliveredDate: deliveredDate,
                      fallbackApplication: fallbackApplication
                  )
            else { continue }
            guard !silenced.contains(notification.applicationIdentifier.lowercased()) else { continue }
            notifications.append(notification)
        }
        return NotificationSnapshot(access: .available, notifications: notifications)
    }

    /// Bit set in an application's notification `flags` when "Allow notifications" is on for it.
    ///
    /// Determined by reading the live settings: this bit is set for every application the user
    /// allows and clear for every one they turn off, across both Apple and third-party apps.
    static let allowNotificationsFlag = 1 << 25

    /// Lowercased bundle identifiers whose notifications the user turned off.
    static func silencedApplications(preferencesURL: URL?) -> Set<String> {
        guard let preferencesURL,
              let data = try? Data(contentsOf: preferencesURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let root = plist as? [String: Any],
              let apps = root["apps"] as? [[String: Any]]
        else {
            return []
        }
        var silenced: Set<String> = []
        for app in apps {
            guard let identifier = app["bundle-id"] as? String, let flags = app["flags"] as? Int else { continue }
            if flags & allowNotificationsFlag == 0 {
                silenced.insert(identifier.lowercased())
            }
        }
        return silenced
    }

    // MARK: - Parsing

    /// UUIDs of every record still shown, concatenated per application in the `delivered` table.
    private func deliveredIdentifiers(_ handle: OpaquePointer) -> Set<Data> {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT list FROM delivered", -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            return []
        }
        defer { sqlite3_finalize(statement) }
        var identifiers: Set<Data> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let list = Self.blob(statement, column: 0) else { continue }
            var offset = 0
            while offset + 16 <= list.count {
                identifiers.insert(list.subdata(in: offset..<(offset + 16)))
                offset += 16
            }
        }
        return identifiers
    }

    /// Decodes one record's property list into a notification.
    static func notification(
        id: String,
        data: Data,
        deliveredDate: Date,
        fallbackApplication: String
    ) -> DeliveredNotification? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let record = plist as? [String: Any]
        else {
            return nil
        }
        let request = record["req"] as? [String: Any] ?? [:]
        let title = Self.trimmed(request["titl"])
        let subtitle = Self.trimmed(request["subt"])
        let body = Self.trimmed(request["body"])
        guard title != nil || body != nil else { return nil }
        let application = Self.trimmed(record["app"]) ?? fallbackApplication
        let date = (record["date"] as? Double).map { Date(timeIntervalSinceReferenceDate: $0) } ?? deliveredDate
        let deepLink = Self.trimmed(request["durl"]).flatMap(URL.init(string:))
        return DeliveredNotification(
            id: id,
            applicationIdentifier: application,
            title: title ?? body ?? "",
            subtitle: subtitle,
            body: title == nil ? nil : body,
            date: date,
            deepLink: deepLink,
            category: Self.trimmed(request["cate"]),
            hints: Self.hints(in: request["usda"] as? Data)
        )
    }

    /// URLs and absolute paths inside the application's archived user data.
    ///
    /// The data is an `NSKeyedArchiver` property list; its strings live in the `$objects` array.
    /// Only strings shaped like a URL or an absolute path are kept, in document order, so nothing
    /// else from the payload is retained. Browser-internal extension origins are dropped because
    /// they cannot be opened.
    static func hints(in data: Data?) -> [String] {
        guard let data,
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let archive = plist as? [String: Any],
              let objects = archive["$objects"] as? [Any]
        else {
            return []
        }
        var hints: [String] = []
        for case let string as String in objects {
            let value = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("/") {
                hints.append(value)
            } else if let url = URL(string: value), let scheme = url.scheme, url.host != nil || scheme != "http",
                      !value.contains(" "), scheme != "chrome-extension", scheme != "moz-extension"
            {
                hints.append(value)
            }
        }
        return hints
    }

    private static func trimmed(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private static func blob(_ statement: OpaquePointer, column: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(statement, column) else { return nil }
        let count = Int(sqlite3_column_bytes(statement, column))
        return Data(bytes: bytes, count: count)
    }
}
