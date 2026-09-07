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

        let source = NotificationCenterSource(databaseURL: url)
        #expect(await source.isAvailable)
        #expect(NotificationCenterSource.accessState(databaseURL: url) == .available)
        let snapshot = await source.read()

        #expect(snapshot.access == .available)
        #expect(snapshot.notifications.map(\.title) == ["Sam", "Build finished"])
        let first = try #require(snapshot.notifications.first)
        #expect(first.applicationIdentifier == "com.apple.MobileSMS")
        #expect(first.body == "On my way")
        #expect(first.date == now)
        #expect(first.id == "000102030405060708090A0B0C0D0E0F")
        let second = try #require(snapshot.notifications.last)
        #expect(second.applicationIdentifier == "com.example.app")
        #expect(second.body == nil)
    }

    // MARK: - Fixture

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
}
