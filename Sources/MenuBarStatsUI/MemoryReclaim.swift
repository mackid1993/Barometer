import Darwin
import OSLog

/// Returns freed malloc pages to the system after a transient surface closes.
///
/// Dropdown panels and the Settings window allocate tens of megabytes of SwiftUI graph state
/// while open. Releasing those objects leaves the pages dirty inside libmalloc, so the process
/// footprint stays near its peak until memory pressure forces a purge. Asking libmalloc to
/// release its free pages right after such a surface closes brings the footprint back down
/// while the machine is idle instead of waiting for pressure.
@MainActor
enum MemoryReclaim {
    private static let logger = Logger(subsystem: "com.barometer.app", category: "memory")
    private static var pendingTask: Task<Void, Never>?

    /// Schedules a pressure relief pass shortly after the caller's teardown has settled.
    ///
    /// The delay lets AppKit finish its own close animations and deferred releases first, and
    /// repeated calls within the window coalesce into one pass.
    static func scheduleRelief(after delay: Duration = .milliseconds(750)) {
        pendingTask?.cancel()
        pendingTask = Task { @MainActor in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            pendingTask = nil
            relieveNow()
        }
    }

    /// Releases free pages from every malloc zone immediately.
    static func relieveNow() {
        let released = malloc_zone_pressure_relief(nil, 0)
        logger.debug("pressure relief released \(released, privacy: .public) bytes")
    }
}
