import Foundation
import SystemSources
import Testing

@testable import MenuBarStatsCore

@Suite("NotificationFeedTests")
@MainActor
struct NotificationFeedTests {
    private static func notification(_ id: String) -> DeliveredNotification {
        DeliveredNotification(
            id: id, applicationIdentifier: "com.example.app", title: "Title \(id)", subtitle: nil, body: nil,
            date: Date(timeIntervalSinceReferenceDate: 800_000_000)
        )
    }

    private static func snapshot(
        _ notifications: [DeliveredNotification],
        deliveredIdentifiers: Set<String>? = nil,
        access: NotificationAccessState = .available,
        hiddenApplicationIdentifiers: Set<String>? = []
    ) -> NotificationSnapshot {
        NotificationSnapshot(
            access: access,
            notifications: notifications,
            deliveredNotificationIdentifiers: deliveredIdentifiers,
            hiddenApplicationIdentifiers: hiddenApplicationIdentifiers
        )
    }

    private static func defaults() throws -> (UserDefaults, String) {
        let suiteName = "NotificationFeedTests-\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suiteName)), suiteName)
    }





    @Test("closing the dropdown during its first read never restarts passive watching")
    func stopDuringStart() async throws {
        let (defaults, suiteName) = try Self.defaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let reads = BlockingNotificationRead()
        let initial = Self.snapshot([])
        let feed = NotificationFeed(preset: initial, defaults: defaults,
                                    readOperation: { await reads.read() }, dismissOperation: { _ in .unavailable })
        let start = Task { await feed.start() }
        while !(await reads.hasStarted) { await Task.yield() }
        feed.stop()
        await reads.finish(with: Self.snapshot([], deliveredIdentifiers: []))
        await start.value
        #expect(!feed.isWatching)
        #expect(feed.snapshot == initial)
    }


    @Test("legacy local dismissals are restored instead of permanently masking system notifications")
    func restoresLegacyDismissals() throws {
        let (defaults, suiteName) = try Self.defaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(["A"], forKey: NotificationFeed.dismissedDefaultsKey)
        let first = Self.notification("A")

        let feed = NotificationFeed(preset: Self.snapshot([first]), defaults: defaults)

        #expect(feed.notifications == [first])
        #expect(defaults.object(forKey: NotificationFeed.dismissedDefaultsKey) == nil)
    }











    @Test("a failed passive read retains the last successful notification list")
    func passiveReadFailureRetainsList() async throws {
        let (defaults, suiteName) = try Self.defaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = Self.notification("A")
        let initial = Self.snapshot([first], deliveredIdentifiers: ["A"])
        let reads = SnapshotRecorder(snapshots: [Self.snapshot(
            [], access: .unavailable, hiddenApplicationIdentifiers: []
        )])
        let feed = NotificationFeed(
            preset: initial,
            defaults: defaults,
            readOperation: { await reads.read() },
            dismissOperation: { _ in .unavailable }
        )

        await feed.refresh()

        #expect(feed.notifications == [first])
        #expect(feed.snapshot?.access == .unavailable)
    }

    @Test("unknown visibility hides cached rows without discarding them")
    func unknownVisibilityRetainsPrivateCache() async throws {
        let (defaults, suiteName) = try Self.defaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = Self.notification("A")
        let reads = SnapshotRecorder(snapshots: [
            Self.snapshot([], access: .unavailable, hiddenApplicationIdentifiers: nil),
            Self.snapshot([], access: .unavailable, hiddenApplicationIdentifiers: []),
            Self.snapshot([], deliveredIdentifiers: [])
        ])
        let feed = NotificationFeed(preset: Self.snapshot([first], deliveredIdentifiers: ["A"]),
            defaults: defaults, readOperation: { await reads.read() }, dismissOperation: { _ in .unavailable })
        await feed.refresh()
        #expect(feed.notifications.isEmpty)
        await feed.refresh()
        #expect(feed.notifications == [first])
        await feed.refresh()
        #expect(feed.notifications.isEmpty)
    }

    @Test("a failed read still excludes applications macOS newly marks hidden")
    func failedReadAppliesHiddenApplications() async throws {
        let (defaults, suiteName) = try Self.defaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = Self.notification("A")
        let initial = Self.snapshot([first], deliveredIdentifiers: ["A"])
        let reads = SnapshotRecorder(snapshots: [Self.snapshot(
            [], access: .unavailable, hiddenApplicationIdentifiers: ["com.example.app"]
        )])
        let feed = NotificationFeed(
            preset: initial,
            defaults: defaults,
            readOperation: { await reads.read() },
            dismissOperation: { _ in .unavailable }
        )

        await feed.refresh()

        #expect(feed.notifications.isEmpty)
        #expect(feed.snapshot?.access == .unavailable)
    }









    @Test("notification clearing is disabled and performs no native action")
    func disabledDismissalHasNoSideEffects() async throws {
        let (defaults, suiteName) = try Self.defaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let notification = Self.notification("A")
        let actions = ActionRecorder(results: ["A": .accepted])
        let emptySnapshot = Self.snapshot([])
        let feed = NotificationFeed(
            preset: Self.snapshot([notification], deliveredIdentifiers: ["A"]),
            defaults: defaults,
            readOperation: { emptySnapshot },
            dismissOperation: { await actions.perform($0) }
        )

        await feed.dismiss(notification)

        #expect(await actions.identifiers.isEmpty)
        #expect(feed.notifications == [notification])
        #expect(feed.dismissalError == "Open Notification Center to clear notifications.")
    }
}

private actor ActionRecorder {
    let results: [String: NotificationSystemActionResult]
    private(set) var identifiers: [String] = []

    init(results: [String: NotificationSystemActionResult]) {
        self.results = results
    }

    func perform(_ notification: DeliveredNotification) -> NotificationSystemActionResult {
        identifiers.append(notification.id)
        return results[notification.id] ?? .failed
    }
}

private actor BlockingActionRecorder {
    private(set) var identifiers: [String] = []
    private var continuation: CheckedContinuation<NotificationSystemActionResult, Never>?

    func perform(_ notification: DeliveredNotification) async -> NotificationSystemActionResult {
        identifiers.append(notification.id)
        return await withCheckedContinuation { continuation = $0 }
    }

    func finish(with result: NotificationSystemActionResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

private actor SnapshotRecorder {
    private var snapshots: [NotificationSnapshot]
    private(set) var readCount = 0

    init(snapshots: [NotificationSnapshot]) {
        self.snapshots = snapshots
    }

    func read() -> NotificationSnapshot {
        readCount += 1
        return snapshots.removeFirst()
    }

}

private actor BlockingNotificationRead {
    private(set) var hasStarted = false
    private var continuation: CheckedContinuation<NotificationSnapshot, Never>?

    func read() async -> NotificationSnapshot {
        hasStarted = true
        return await withCheckedContinuation { continuation = $0 }
    }

    func finish(with snapshot: NotificationSnapshot) {
        continuation?.resume(returning: snapshot)
        continuation = nil
    }

}
