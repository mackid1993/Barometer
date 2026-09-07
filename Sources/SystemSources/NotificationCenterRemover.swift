import Darwin
import Foundation
import OSLog
import SQLite3

/// How a system-level removal ended.
public enum NotificationRemovalResult: Equatable, Sendable {
    /// The rows are gone from Notification Center's database and its daemon reloaded the list.
    case removed
    /// The database could not be opened for writing; nothing changed.
    case unavailable(String)
    /// The write or the daemon restart failed after the attempt began.
    case failed(String)
}

/// Clears another application's notifications from macOS by editing Notification Center's own list.
///
/// macOS gives an ordinary process no interface for dismissing another application's notification:
/// the public API covers only the caller's own, the daemon's dismissal message is accepted only from
/// Notification Center itself, and the panel's Accessibility rows exist only while it is open or a
/// banner is on screen. What remains is the store itself. Notification Center persists its list in an
/// SQLite database (readable and writable with Full Disk Access): a `record` row per notification and,
/// per application, a `delivered` blob of the 16-byte UUIDs still shown. Removing a notification means
/// deleting its row and stripping exactly its UUID from every list blob, then restarting the daemon
/// that owns the file, usernoted, which launchd relaunches at once and which reloads the list from
/// disk. Verified on macOS 27.0: the row stayed deleted after the relaunch and the other entries in
/// the same application's list were untouched.
///
/// This is the approach community clear-all scripts have used for years, made surgical. The one cost
/// is the restart: a banner arriving in that instant can be lost. David chose it on 2026-09-07 over
/// leaving clears local to Barometer. Only exact UUIDs the caller names are ever touched.
public actor NotificationCenterRemover {
    private let databaseURL: URL
    private let restart: @Sendable () async -> Bool
    private let logger = Logger(subsystem: "com.barometer.app", category: "notification-remover")

    /// Creates a remover over the real database, queuing a restart of the notification processes after each write.
    public init(
        databaseURL: URL = NotificationCenterSource.defaultDatabaseURL,
        restart: @escaping @Sendable () async -> Bool = { await NotificationDaemonRestarter.shared.requestRestart() }
    ) {
        self.databaseURL = databaseURL
        self.restart = restart
    }

    /// Removes exactly the notifications whose identifiers (uppercase UUID hex) are given.
    public func remove(identifiers: Set<String>) async -> NotificationRemovalResult {
        let targets = identifiers.compactMap(Self.uuidData)
        guard !targets.isEmpty else { return .removed }
        guard NotificationCenterSource.accessState(databaseURL: databaseURL) == .available else {
            return .unavailable("Barometer needs Full Disk Access to clear notifications from macOS.")
        }

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(databaseURL.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "no handle"
            if let handle { sqlite3_close(handle) }
            logger.error("notification database open for writing failed: \(message, privacy: .public)")
            return .unavailable("Notification Center's database could not be opened for writing.")
        }
        defer { sqlite3_close(handle) }
        sqlite3_busy_timeout(handle, 1_000)

        guard sqlite3_exec(handle, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil) == SQLITE_OK else {
            return .failed(Self.message(handle, "Notification Center's database is busy."))
        }
        do {
            for target in targets {
                try Self.run(handle, "DELETE FROM record WHERE uuid = ?", blobs: [target])
            }
            for table in ["delivered", "displayed", "requests"] {
                try Self.strip(handle, table: table, targets: Set(targets))
            }
            guard sqlite3_exec(handle, "COMMIT", nil, nil, nil) == SQLITE_OK else {
                throw WriteError(message: Self.message(handle, "The change could not be committed."))
            }
        } catch let error as WriteError {
            sqlite3_exec(handle, "ROLLBACK", nil, nil, nil)
            logger.error("notification removal failed: \(error.message, privacy: .public)")
            return .failed(error.message)
        } catch {
            sqlite3_exec(handle, "ROLLBACK", nil, nil, nil)
            return .failed(String(describing: error))
        }
        logger.notice("removed \(targets.count) notification record(s) from Notification Center's database")

        // The write is the result: Barometer's list reads from the database. The restarts that make the
        // panel catch up are queued and coalesced, because launchd holds a service back for about ten
        // seconds after a rapid relaunch and a burst of clears must not each wait on that.
        guard await restart() else {
            return .failed("The notifications were removed from the database, but the notification processes could not be restarted.")
        }
        return .removed
    }

    // MARK: - SQL

    private struct WriteError: Error { let message: String }

    /// Rewrites each list blob in `table` without the target UUIDs, touching only rows that change.
    private static func strip(_ handle: OpaquePointer, table: String, targets: Set<Data>) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT app_id, list FROM \(table)", -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            // Not every build has every table; a missing one holds nothing to strip.
            return
        }
        var updates: [(appID: Int64, list: Data)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let appID = sqlite3_column_int64(statement, 0)
            guard let list = blob(statement, column: 1) else { continue }
            var kept = Data()
            var offset = 0
            var changed = false
            while offset + 16 <= list.count {
                let chunk = list.subdata(in: offset..<(offset + 16))
                if targets.contains(chunk) { changed = true } else { kept.append(chunk) }
                offset += 16
            }
            if changed { updates.append((appID, kept)) }
        }
        sqlite3_finalize(statement)
        for update in updates {
            try run(handle, "UPDATE \(table) SET list = ? WHERE app_id = \(update.appID)", blobs: [update.list])
        }
    }

    private static func run(_ handle: OpaquePointer, _ sql: String, blobs: [Data]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw WriteError(message: message(handle, "The database statement could not be prepared."))
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, blob) in blobs.enumerated() {
            let bound = blob.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, Int32(index + 1), bytes.baseAddress, Int32(blob.count), transient)
            }
            guard bound == SQLITE_OK else { throw WriteError(message: message(handle, "A value could not be bound.")) }
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw WriteError(message: message(handle, "The database statement failed."))
        }
    }

    private static func message(_ handle: OpaquePointer, _ fallback: String) -> String {
        let text = String(cString: sqlite3_errmsg(handle))
        return text.isEmpty || text == "not an error" ? fallback : "\(fallback) (\(text))"
    }

    private static func blob(_ statement: OpaquePointer, column: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(statement, column) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
    }

    /// The 16 bytes behind an uppercase-hex notification identifier, or nil for anything else.
    static func uuidData(_ identifier: String) -> Data? {
        let hex = Array(identifier.utf8)
        guard hex.count == 32 else { return nil }
        var data = Data(capacity: 16)
        var index = 0
        while index < 32 {
            guard let high = hexValue(hex[index]), let low = hexValue(hex[index + 1]) else { return nil }
            data.append(high << 4 | low)
            index += 2
        }
        return data
    }

    private static func hexValue(_ character: UInt8) -> UInt8? {
        switch character {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): character - UInt8(ascii: "0")
        case UInt8(ascii: "A")...UInt8(ascii: "F"): character - UInt8(ascii: "A") + 10
        case UInt8(ascii: "a")...UInt8(ascii: "f"): character - UInt8(ascii: "a") + 10
        default: nil
        }
    }
}

/// Brings the notification processes back in line with the database after a removal.
///
/// usernoted owns the database and reloads it only on relaunch; the NotificationCenter process that
/// draws the panel keeps its own copy of the list and shows the old entries until it, too, relaunches.
/// Both are launchd agents. Each is restarted through `launchctl kickstart -k`, an explicit request
/// that launchd honors immediately rather than the exit throttle it applies to a service that keeps
/// dying on its own. The order matters: the panel must reconnect to a daemon that has already reloaded.
///
/// The database write is the result; this sync is only how Apple's panel catches up. It therefore runs
/// as one coalesced background job: a burst of clears, or a Clear All, costs one restart of each
/// process, and a request that arrives mid-sync simply runs the sync once more when it finishes. A
/// clear never waits on it and never fails because of it.
public actor NotificationDaemonRestarter {
    /// The one sync worker for the process.
    public static let shared = NotificationDaemonRestarter()

    static let daemonName = "usernoted"
    static let daemonLabel = "com.apple.usernoted"
    static let panelName = "NotificationCenter"
    static let panelLabel = "com.apple.notificationcenterui"
    private static let logger = Logger(subsystem: "com.barometer.app", category: "notification-remover")

    private var syncTask: Task<Void, Never>?
    private var pending = false

    /// Schedules one sync of the notification processes and returns at once.
    ///
    /// Always true: the caller's database write already succeeded, and the sync reports its own
    /// outcome to the log. Repeated calls while a sync runs fold into a single follow-up pass.
    public func requestRestart() -> Bool {
        pending = true
        if syncTask == nil {
            syncTask = Task { await runSync() }
        }
        return true
    }

    private func runSync() async {
        while pending {
            pending = false
            let daemon = await Self.kickstart(name: Self.daemonName, label: Self.daemonLabel)
            if daemon {
                _ = await Self.kickstart(name: Self.panelName, label: Self.panelLabel)
            }
        }
        syncTask = nil
    }

    /// Asks launchd to restart the agent and waits for a new instance to appear.
    static func kickstart(name: String, label: String) async -> Bool {
        let before = processIdentifiers(named: name)
        let target = "gui/\(getuid())/\(label)"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["kickstart", "-k", target]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            logger.error("launchctl could not run for \(label, privacy: .public): \(String(describing: error), privacy: .public)")
            return false
        }
        guard process.terminationStatus == 0 else {
            logger.error("launchctl kickstart \(label, privacy: .public) exited \(process.terminationStatus)")
            return false
        }
        for _ in 0..<150 {
            try? await Task.sleep(for: .milliseconds(100))
            let now = processIdentifiers(named: name)
            if !now.isEmpty, now.isDisjoint(with: before) {
                logger.notice("\(name, privacy: .public) restarted as \(now.sorted(), privacy: .public)")
                return true
            }
        }
        logger.error("\(name, privacy: .public) did not come back within fifteen seconds")
        return false
    }

    /// Process identifiers whose executable name matches, for this user only.
    static func processIdentifiers(named name: String) -> Set<pid_t> {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) * 2)
        let filled = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<pid_t>.size))
        }
        guard filled > 0 else { return [] }
        var matches: Set<pid_t> = []
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        for pid in pids.prefix(Int(filled)) where pid > 0 {
            guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { continue }
            guard String(cString: buffer) == name else { continue }
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, info.pbi_uid == getuid() else { continue }
            matches.insert(pid)
        }
        return matches
    }
}
