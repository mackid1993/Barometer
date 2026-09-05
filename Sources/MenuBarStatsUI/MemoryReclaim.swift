import Darwin
import OSLog

/// Returns freed malloc pages to the system after a transient SwiftUI surface closes.
@MainActor
enum MemoryReclaim {
    private static let logger = Logger(subsystem: "com.barometer.app", category: "memory")
    private static var pendingTask: Task<Void, Never>?

    /// Coalesces nearby closures and waits for AppKit's deferred teardown before releasing pages.
    static func scheduleRelief(after delay: Duration = .milliseconds(750)) {
        pendingTask?.cancel()
        pendingTask = Task { @MainActor in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            let firstRelease = malloc_zone_pressure_relief(nil, 0)
            logger.debug("pressure relief released \(firstRelease, privacy: .public) bytes")
            do {
                // SwiftUI and Core Animation complete part of their teardown on later run-loop turns.
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
            let deferredRelease = malloc_zone_pressure_relief(nil, 0)
            logger.debug("deferred pressure relief released \(deferredRelease, privacy: .public) bytes")
            pendingTask = nil
        }
    }
}
