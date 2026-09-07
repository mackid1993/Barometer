import Foundation
import SQLite3
import Testing
@testable import SystemSources

@Suite("NotificationCenterSourceTests")
struct NotificationCenterSourceTests {
    @Test("a missing database reports unavailable and reads nothing")
    func missingDatabase() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BarometerNotifications-\(UUID().uuidString)/db")
        let source = NotificationCenterSource(databaseURL: url)
        #expect(await source.isAvailable == false)
        #expect(NotificationCenterSource.accessState(databaseURL: url) == .unavailable)
        let snapshot = await source.read()
        #expect(snapshot.access == .unavailable)
        #expect(snapshot.notifications.isEmpty)
    }

    @Test("only records listed as delivered are read, newest first, with their request text")
    func readsDeliveredRecords() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BarometerNotifications-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("db")

        let shownUUID = Data((0..<16).map { UInt8($0) })
        let olderUUID = Data((16..<32).map { UInt8($0) })
        let dismissedUUID = Data((32..<48).map { UInt8($0) })
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        try Self.writeFixture(
            at: url,
            apps: [(1, "com.apple.mobilesms"), (2, "com.example.app")],
            records: [
                (1, shownUUID, Self.record(app: "com.apple.MobileSMS", title: "Sam", body: "On my way",
                                           date: now), now),
                (2, olderUUID, Self.record(app: nil, title: "Build finished", body: nil,
                                           date: now.addingTimeInterval(-60)), now.addingTimeInterval(-60)),
                (2, dismissedUUID, Self.record(app: "com.example.app", title: "Dismissed", body: "gone",
                                               date: now), now),
            ],
            scheduled: [(2, Data((48..<64).map { UInt8($0) }), Self.record(app: nil, title: "Later", body: nil,
                                                                             date: now))],
            delivered: [(1, shownUUID), (2, olderUUID)]
        )

        let source = NotificationCenterSource(databaseURL: url, preferencesURL: nil)
        #expect(await source.isAvailable)
        #expect(NotificationCenterSource.accessState(databaseURL: url) == .available)
        let snapshot = await source.read()

        #expect(snapshot.access == .available)
        #expect(snapshot.notifications.map(\.title) == ["Sam", "Build finished"])
        #expect(snapshot.deliveredNotificationIdentifiers == [
            "000102030405060708090A0B0C0D0E0F",
            "101112131415161718191A1B1C1D1E1F",
        ])

        // An application whose notifications are turned off keeps its records, but the list hides them.
        // The allow bit (1 << 25) in `flags` is the signal, not `auth`: a silenced app can still hold a
        // nonzero auth, which is exactly the Messages case a naive auth check missed.
        let preferences = directory.appendingPathComponent("prefs.plist")
        let settings: [String: Any] = ["apps": [
            ["bundle-id": "com.Example.App", "auth": 791, "flags": 268_443_662],  // bit 25 clear: off
            ["bundle-id": "com.apple.MobileSMS", "auth": 7, "flags": 41_951_246],  // bit 25 set: on
        ]]
        try PropertyListSerialization.data(fromPropertyList: settings, format: .binary, options: 0)
            .write(to: preferences)
        #expect(NotificationCenterSource.silencedApplications(preferencesURL: preferences) == ["com.example.app"])
        let filtered = await NotificationCenterSource(databaseURL: url, preferencesURL: preferences).read()
        #expect(filtered.notifications.map(\.title) == ["Sam"])
        let first = try #require(snapshot.notifications.first)
        #expect(first.applicationIdentifier == "com.apple.MobileSMS")
        #expect(first.body == "On my way")
        #expect(first.date == now)
        #expect(first.id == "000102030405060708090A0B0C0D0E0F")
        let second = try #require(snapshot.notifications.last)
        #expect(second.applicationIdentifier == "com.example.app")
        #expect(second.body == nil)

        let limited = await source.read(limit: 1)
        #expect(limited.notifications.map(\.title) == ["Sam"])
        #expect(limited.deliveredNotificationIdentifiers == snapshot.deliveredNotificationIdentifiers)
    }

    @Test("a schema or query failure is not reported as a successful empty read")
    func schemaFailure() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BarometerNotifications-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("db")

        var handle: OpaquePointer?
        try #require(sqlite3_open(url.path, &handle) == SQLITE_OK)
        try #require(sqlite3_exec(handle, "CREATE TABLE delivered (app_id INTEGER PRIMARY KEY, list BLOB)",
                                  nil, nil, nil) == SQLITE_OK)
        sqlite3_close(handle)

        let snapshot = await NotificationCenterSource(databaseURL: url, preferencesURL: nil).read()
        #expect(snapshot.access == .unavailable)
        #expect(snapshot.notifications.isEmpty)
        #expect(snapshot.deliveredNotificationIdentifiers == nil)
    }

    @Test("an empty delivered list is authoritative, while a partial UUID is malformed")
    func deliveredListValidation() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BarometerNotifications-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let emptyURL = directory.appendingPathComponent("empty-db")
        try Self.writeFixture(at: emptyURL, apps: [(1, "com.example.app")], records: [], scheduled: [], delivered: [])
        try Self.insertDeliveredList(Data(), app: 1, at: emptyURL)
        let empty = await NotificationCenterSource(databaseURL: emptyURL, preferencesURL: nil).read()
        #expect(empty.access == .available)
        #expect(empty.deliveredNotificationIdentifiers == [])

        let malformedURL = directory.appendingPathComponent("malformed-db")
        try Self.writeFixture(
            at: malformedURL,
            apps: [(1, "com.example.app")],
            records: [],
            scheduled: [],
            delivered: []
        )
        try Self.insertDeliveredList(Data([0]), app: 1, at: malformedURL)
        let malformed = await NotificationCenterSource(databaseURL: malformedURL, preferencesURL: nil).read()
        #expect(malformed.access == .unavailable)
        #expect(malformed.deliveredNotificationIdentifiers == nil)
    }

    @Test("nullable empty application lists and unreadable previews do not drop delivered notifications")
    func emptyApplicationAndUnavailablePreview() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BarometerNotifications-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("db")
        let uuid = Data((0..<16).map { UInt8($0) })
        let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
        try Self.writeFixture(at: url, apps: [(1, "com.example.app"), (2, "com.example.empty")],
            records: [(1, uuid, Data([0]), date)], scheduled: [], delivered: [(1, uuid)])
        var handle: OpaquePointer?
        try #require(sqlite3_open(url.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        try #require(sqlite3_exec(handle, "INSERT INTO delivered (app_id, list) VALUES (2, NULL)",
                                 nil, nil, nil) == SQLITE_OK)
        let snapshot = await NotificationCenterSource(databaseURL: url, preferencesURL: nil).read()
        #expect(snapshot.access == .available)
        #expect(snapshot.notifications.count == 1)
        #expect(snapshot.notifications.first?.title == "")
        #expect(snapshot.notifications.first?.applicationIdentifier == "com.example.app")
        #expect(snapshot.deliveredNotificationIdentifiers == ["000102030405060708090A0B0C0D0E0F"])
    }

    @Test("unreadable macOS visibility preferences never expose excluded applications")
    func unavailableVisibilityPreferences() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BarometerNotifications-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("db")
        try Self.writeFixture(at: url, apps: [], records: [], scheduled: [], delivered: [])
        let snapshot = await NotificationCenterSource(databaseURL: url,
            preferencesURL: directory.appendingPathComponent("missing.plist")).read()
        #expect(snapshot.access == .unavailable)
        #expect(snapshot.hiddenApplicationIdentifiers == nil)
        #expect(snapshot.notifications.isEmpty)
    }

    @Test("records expose their deep link, category, and the URLs and paths in user data")
    func routingFields() throws {
        let archive: [String: Any] = [
            "$archiver": "NSKeyedArchiver", "$version": 100_000, "$top": ["root": 1],
            "$objects": [
                "$null", "chrome-extension://abc/", "https://example.com/item/7", "/Users/me/Downloads/a.zip",
                "plain text", "not a url", 42,
            ],
        ]
        let userData = try PropertyListSerialization.data(fromPropertyList: archive, format: .binary, options: 0)
        let record: [String: Any] = [
            "app": "com.apple.MobileSMS", "date": 800_000_000.0,
            "req": ["titl": "Sam", "body": "Hi", "durl": "messages://open?chat=1", "cate": "IncomingMessage",
                    "usda": userData],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: record, format: .binary, options: 0)
        let parsed = try #require(NotificationCenterSource.notification(
            id: "A", data: data, deliveredDate: Date(), fallbackApplication: "x"))
        #expect(parsed.deepLink == URL(string: "messages://open?chat=1"))
        #expect(parsed.category == "IncomingMessage")
        #expect(parsed.hints == ["https://example.com/item/7", "/Users/me/Downloads/a.zip"])
    }

    // MARK: - Fixture

    @Test("delivered notifications without preview text remain in the mirrored list")
    func textlessNotification() throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["app": "com.example.app", "req": [:]] as [String: Any], format: .binary, options: 0)
        let notification = try #require(NotificationCenterSource.notification(
            id: "A", data: data, deliveredDate: Date(), fallbackApplication: "com.example.app"))
        #expect(notification.title.isEmpty)
        #expect(notification.body == nil)
    }

    @Test("watching includes notification settings so silencing changes refresh the list")
    func watchesPreferences() async {
        let preferences = URL(fileURLWithPath: "/tmp/barometer-notification-preferences/settings.plist")
        let source = NotificationCenterSource(databaseURL: URL(fileURLWithPath: "/tmp/barometer-notification-db"),
                                              preferencesURL: preferences)
        let urls = await source.watchedURLs
        #expect(urls.contains(preferences))
        #expect(urls.contains(preferences.deletingLastPathComponent()))
    }

    @Test("the default read mirrors more than one hundred delivered notifications")
    func fullDeliveredList() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BarometerNotifications-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("db")
        let uuids = (0..<105).map { index -> Data in
            var uuid = Data(repeating: 0, count: 16)
            uuid[15] = UInt8(index)
            return uuid
        }
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        try Self.writeFixture(
            at: url, apps: [(1, "com.example.app")],
            records: uuids.enumerated().map { index, uuid in
                let date = now.addingTimeInterval(Double(index))
                return (1, uuid, Self.record(app: nil, title: "Notification \(index)", body: nil, date: date), date)
            }, scheduled: [], delivered: uuids.map { (1, $0) })
        let snapshot = await NotificationCenterSource(databaseURL: url, preferencesURL: nil).read()
        #expect(snapshot.access == .available)
        #expect(snapshot.notifications.count == 105)
        #expect(snapshot.notifications.first?.title == "Notification 104")
        #expect(snapshot.notifications.last?.title == "Notification 0")
    }

    private static func record(app: String?, title: String, body: String?, date: Date) -> Data {
        var request: [String: Any] = ["titl": title]
        if let body { request["body"] = body }
        var record: [String: Any] = ["req": request, "date": date.timeIntervalSinceReferenceDate]
        if let app { record["app"] = app }
        return try! PropertyListSerialization.data(fromPropertyList: record, format: .binary, options: 0)
    }

    private static func writeFixture(
        at url: URL,
        apps: [(Int, String)],
        records: [(Int, Data, Data, Date)],
        scheduled: [(Int, Data, Data)],
        delivered: [(Int, Data)]
    ) throws {
        var handle: OpaquePointer?
        try #require(sqlite3_open(url.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        for sql in [
            "CREATE TABLE app (app_id INTEGER PRIMARY KEY, identifier VARCHAR, badge INTEGER NULL)",
            """
            CREATE TABLE record (rec_id INTEGER PRIMARY KEY, app_id INTEGER, uuid BLOB, data BLOB,
            request_date REAL, request_last_date REAL, delivered_date REAL, presented Bool, style INTEGER,
            snooze_fire_date REAL)
            """,
            "CREATE TABLE delivered (app_id INTEGER PRIMARY KEY, list BLOB)",
        ] {
            try #require(sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK)
        }
        for (id, identifier) in apps {
            try #require(sqlite3_exec(
                handle, "INSERT INTO app (app_id, identifier) VALUES (\(id), '\(identifier)')", nil, nil, nil
            ) == SQLITE_OK)
        }
        let insert = "INSERT INTO record (app_id, uuid, data, delivered_date) VALUES (?, ?, ?, ?)"
        for (app, uuid, data, date) in records {
            try insertRecord(handle, sql: insert, app: app, uuid: uuid, data: data, date: date)
        }
        for (app, uuid, data) in scheduled {
            try insertRecord(handle, sql: insert, app: app, uuid: uuid, data: data, date: nil)
        }
        var lists: [Int: Data] = [:]
        for (app, uuid) in delivered { lists[app, default: Data()].append(uuid) }
        for (app, list) in lists {
            var statement: OpaquePointer?
            try #require(sqlite3_prepare_v2(handle, "INSERT INTO delivered (app_id, list) VALUES (?, ?)", -1,
                                            &statement, nil) == SQLITE_OK)
            sqlite3_bind_int(statement, 1, Int32(app))
            try list.withUnsafeBytes { bytes in
                try #require(sqlite3_bind_blob(statement, 2, bytes.baseAddress, Int32(list.count),
                                               unsafeBitCast(-1, to: sqlite3_destructor_type.self)) == SQLITE_OK)
            }
            try #require(sqlite3_step(statement) == SQLITE_DONE)
            sqlite3_finalize(statement)
        }
    }

    private static func insertRecord(
        _ handle: OpaquePointer?, sql: String, app: Int, uuid: Data, data: Data, date: Date?
    ) throws {
        var statement: OpaquePointer?
        try #require(sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_int(statement, 1, Int32(app))
        try uuid.withUnsafeBytes { bytes in
            try #require(sqlite3_bind_blob(statement, 2, bytes.baseAddress, Int32(uuid.count), transient) == SQLITE_OK)
        }
        try data.withUnsafeBytes { bytes in
            try #require(sqlite3_bind_blob(statement, 3, bytes.baseAddress, Int32(data.count), transient) == SQLITE_OK)
        }
        if let date {
            sqlite3_bind_double(statement, 4, date.timeIntervalSinceReferenceDate)
        } else {
            sqlite3_bind_null(statement, 4)
        }
        try #require(sqlite3_step(statement) == SQLITE_DONE)
    }

    private static func insertDeliveredList(_ list: Data, app: Int, at url: URL) throws {
        var handle: OpaquePointer?
        try #require(sqlite3_open(url.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        var statement: OpaquePointer?
        try #require(sqlite3_prepare_v2(
            handle,
            "INSERT INTO delivered (app_id, list) VALUES (?, ?)",
            -1,
            &statement,
            nil
        ) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(app))
        try list.withUnsafeBytes { bytes in
            let pointer = bytes.baseAddress ?? UnsafeRawPointer(bitPattern: 1)
            try #require(sqlite3_bind_blob(
                statement,
                2,
                pointer,
                Int32(list.count),
                unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            ) == SQLITE_OK)
        }
        try #require(sqlite3_step(statement) == SQLITE_DONE)
    }
}
