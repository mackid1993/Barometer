import Foundation
import SQLite3
import Testing
@testable import SystemSources

@Suite("NotificationCenterRemoverTests")
struct NotificationCenterRemoverTests {
    @Test("only the named UUIDs leave the record table and every list blob, then the daemon restarts once")
    func removesExactly() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BarometerRemover-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("db")
        let keep = Data((0..<16).map { UInt8($0) })
        let gone = Data((16..<32).map { UInt8($0) })
        let other = Data((32..<48).map { UInt8($0) })
        try Self.writeFixture(at: url, records: [(1, keep), (1, gone), (2, other)],
                              delivered: [(1, keep + gone), (2, other)], displayed: [(1, gone)])

        let restarts = RestartCounter()
        let remover = NotificationCenterRemover(databaseURL: url, restart: { await restarts.increment(); return true })
        let goneIdentifier = gone.map { String(format: "%02X", $0) }.joined()
        #expect(await remover.remove(identifiers: [goneIdentifier]) == .removed)
        #expect(await restarts.count == 1)

        var handle: OpaquePointer?
        try #require(sqlite3_open(url.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        #expect(Self.blobs(handle, "SELECT uuid FROM record ORDER BY rec_id") == [keep, other])
        #expect(Self.blobs(handle, "SELECT list FROM delivered ORDER BY app_id") == [keep, other])
        #expect(Self.blobs(handle, "SELECT list FROM displayed ORDER BY app_id") == [Data()])

        // Nothing to do is not a failure, and a bad identifier is ignored rather than guessed at.
        #expect(await remover.remove(identifiers: ["not-a-uuid"]) == .removed)
        #expect(await restarts.count == 1)
    }

    @Test("a failed daemon restart is reported after the rows are gone")
    func restartFailure() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BarometerRemover-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("db")
        let gone = Data((16..<32).map { UInt8($0) })
        try Self.writeFixture(at: url, records: [(1, gone)], delivered: [(1, gone)], displayed: [])
        let remover = NotificationCenterRemover(databaseURL: url, restart: { false })
        let result = await remover.remove(identifiers: [gone.map { String(format: "%02X", $0) }.joined()])
        guard case .failed = result else {
            Issue.record("expected a failure, got \(result)")
            return
        }
    }

    @Test("a missing database is unavailable and touches nothing")
    func missing() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BarometerRemover-missing/db")
        let remover = NotificationCenterRemover(databaseURL: url, restart: { true })
        guard case .unavailable = await remover.remove(identifiers: [String(repeating: "A", count: 32)]) else {
            Issue.record("expected unavailable")
            return
        }
    }

    // MARK: - Fixture

    private actor RestartCounter {
        var count = 0
        func increment() { count += 1 }
    }

    private static func blobs(_ handle: OpaquePointer?, _ sql: String) -> [Data] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var results: [Data] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let bytes = sqlite3_column_blob(statement, 0) {
                results.append(Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0))))
            } else {
                results.append(Data())
            }
        }
        return results
    }

    private static func writeFixture(
        at url: URL, records: [(Int, Data)], delivered: [(Int, Data)], displayed: [(Int, Data)]
    ) throws {
        var handle: OpaquePointer?
        try #require(sqlite3_open(url.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        for sql in [
            "CREATE TABLE record (rec_id INTEGER PRIMARY KEY, app_id INTEGER, uuid BLOB, data BLOB, delivered_date REAL)",
            "CREATE TABLE delivered (app_id INTEGER PRIMARY KEY, list BLOB)",
            "CREATE TABLE displayed (app_id INTEGER PRIMARY KEY, list BLOB)",
        ] {
            try #require(sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK)
        }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        func insert(_ sql: String, _ app: Int, _ blob: Data) throws {
            var statement: OpaquePointer?
            try #require(sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK)
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int(statement, 1, Int32(app))
            try blob.withUnsafeBytes { bytes in
                try #require(sqlite3_bind_blob(statement, 2, bytes.baseAddress, Int32(blob.count), transient) == SQLITE_OK)
            }
            try #require(sqlite3_step(statement) == SQLITE_DONE)
        }
        for (app, uuid) in records {
            try insert("INSERT INTO record (app_id, uuid, delivered_date) VALUES (?, ?, 1)", app, uuid)
        }
        for (app, list) in delivered { try insert("INSERT INTO delivered (app_id, list) VALUES (?, ?)", app, list) }
        for (app, list) in displayed { try insert("INSERT INTO displayed (app_id, list) VALUES (?, ?)", app, list) }
    }
}
