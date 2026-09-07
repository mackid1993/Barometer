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
        access: NotificationAccessState = .available
    ) -> NotificationSnapshot {
        NotificationSnapshot(
            access: access,
            notifications: notifications,
            deliveredNotificationIdentifiers: deliveredIdentifiers
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

    @Test("a requested clear still completes when the dropdown closes")
    func clearFinishesAfterClose() async throws {
        let (defaults, suiteName) = try Self.defaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = Self.notification("A")
        let action = BlockingActionRecorder()
        let reads = SnapshotRecorder(snapshots: [Self.snapshot([], deliveredIdentifiers: [])])
        let feed = NotificationFeed(preset: Self.snapshot([first], deliveredIdentifiers: ["A"]), defaults: defaults,
                                    readOperation: { await reads.read() },
                                    dismissOperation: { await action.perform($0) })
        let clear = Task { await feed.dismiss(first) }
        while (await action.identifiers).isEmpty { await Task.yield() }
        feed.stop()
        await action.finish(with: .accepted)
        await clear.value
        #expect(feed.notifications.isEmpty)
        #expect(feed.dismissalError == nil)
        #expect(!feed.isWatching)
        #expect(!feed.isDismissing)
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

    @Test("an accepted clear removes a row only after an authoritative refresh proves it disappeared")
    func verifiesAcceptedDismissal() async throws {
        let (defaults, suiteName) = try Self.defaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = Self.notification("A")
        let second = Self.notification("B")
        let actions = ActionRecorder(results: ["A": .accepted])
        let reads = SnapshotRecorder(snapshots: [Self.snapshot([second], deliveredIdentifiers: ["B"])])
        let feed = NotificationFeed(
            preset: Self.snapshot([first, second], deliveredIdentifiers: ["A", "B"]),
            defaults: defaults,
            readOperation: { await reads.read() },
            dismissOperation: { await actions.perform($0) }
        )

        await feed.dismiss(first)

        #expect(await actions.identifiers == ["A"])
        #expect(await reads.readCount == 1)
        #expect(feed.notifications == [second])
        #expect(feed.dismissalError == nil)
        #expect(!feed.isDismissing)
    }

    @Test("an accepted action retains the row when the authoritative refresh still contains it")
    func retainsUnclearedAcceptedDismissal() async throws {
        let (defaults, suiteName) = try Self.defaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = Self.notification("A")
        let initial = Self.snapshot([first], deliveredIdentifiers: ["A"])
        let actions = ActionRecorder(results: ["A": .accepted])
        let reads = SnapshotRecorder(snapshots: [Self.snapshot([], deliveredIdentifiers: ["A"])])
        let feed = NotificationFeed(
            preset: initial,
            defaults: defaults,
            readOperation: { await reads.read() },
            dismissOperation: { await actions.perform($0) }
        )

        await feed.dismiss(first)

        #expect(feed.notifications == [first])
        #expect(feed.dismissalError?.contains("still present") == true)
    }

    @Test("dismissal verification retries while Notification Center commits an accepted action")
    func retriesAcceptedDismissalVerification() async throws {
        let (defaults, suiteName) = try Self.defaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = Self.notification("A")
        let initial = Self.snapshot([first], deliveredIdentifiers: ["A"])
        let actions = ActionRecorder(results: ["A": .accepted])
        let reads = SnapshotRecorder(snapshots: [
            Self.snapshot([first], deliveredIdentifiers: ["A"]),
            Self.snapshot([], deliveredIdentifiers: []),
        ])
        let feed = NotificationFeed(
            preset: initial,
            defaults: defaults,
            readOperation: { await reads.read() },
            dismissOperation: { await actions.perform($0) },
            dismissalVerificationDelays: [.milliseconds(1)]
        )

        await feed.dismiss(first)

        #expect(await reads.readCount == 2)
        #expect(feed.notifications.isEmpty)
        #expect(feed.dismissalError == nil)
    }

    @Test("an unavailable native action retains the row and does not claim a refresh verified it")
    func retainsUnavailableDismissal() async throws {
        let (defaults, suiteName) = try Self.defaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = Self.notification("A")
        let initial = Self.snapshot([first], deliveredIdentifiers: ["A"])
        let actions = ActionRecorder(results: ["A": .unavailable])
        let reads = SnapshotRecorder(snapshots: [Self.snapshot([], deliveredIdentifiers: [])])
        let feed = NotificationFeed(
            preset: initial,
            defaults: defaults,
            readOperation: { await reads.read() },
            dismissOperation: { await actions.perform($0) }
        )

        await feed.dismiss(first)

        #expect(feed.notifications == [first])
        #expect(feed.dismissalError?.contains("Notification Center") == true)
        #expect(await reads.readCount == 0)
    }

    @Test("clear shown dispatches only supplied rows and retains partial failures")
    func clearsOnlySuppliedRows() async throws {
        let (defaults, suiteName) = try Self.defaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = Self.notification("A")
        let second = Self.notification("B")
        let unseen = Self.notification("C")
        let actions = ActionRecorder(results: ["A": .accepted, "B": .failed])
        let reads = SnapshotRecorder(snapshots: [Self.snapshot(
            [second, unseen], deliveredIdentifiers: ["B", "C"]
        )])
        let feed = NotificationFeed(
            preset: Self.snapshot([first, second, unseen], deliveredIdentifiers: ["A", "B", "C"]),
            defaults: defaults,
            readOperation: { await reads.read() },
            dismissOperation: { await actions.perform($0) }
        )

        await feed.dismiss([first, second, first])

        #expect(await actions.identifiers == ["A", "B"])
        #expect(feed.notifications == [second, unseen])
        #expect(feed.dismissalError?.contains("did not clear") == true)
    }

    @Test("an unverifiable refresh retains the prior rows")
    func retainsRowsWhenVerificationFails() async throws {
        let (defaults, suiteName) = try Self.defaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = Self.notification("A")
        let initial = Self.snapshot([first], deliveredIdentifiers: ["A"])
        let actions = ActionRecorder(results: ["A": .accepted])
        let reads = SnapshotRecorder(snapshots: [Self.snapshot([], access: .unavailable)])
        let feed = NotificationFeed(
            preset: initial,
            defaults: defaults,
            readOperation: { await reads.read() },
            dismissOperation: { await actions.perform($0) }
        )

        await feed.dismiss(first)

        #expect(feed.snapshot == initial)
        #expect(feed.notifications == [first])
        #expect(feed.dismissalError?.contains("could not verify") == true)
    }

    @Test("a repeated clear is ignored while another clear is in flight")
    func ignoresConcurrentDismissal() async throws {
        let (defaults, suiteName) = try Self.defaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = Self.notification("A")
        let second = Self.notification("B")
        let actions = BlockingActionRecorder()
        let reads = SnapshotRecorder(snapshots: [Self.snapshot([second], deliveredIdentifiers: ["B"])])
        let feed = NotificationFeed(
            preset: Self.snapshot([first, second], deliveredIdentifiers: ["A", "B"]),
            defaults: defaults,
            readOperation: { await reads.read() },
            dismissOperation: { await actions.perform($0) }
        )

        let firstRequest = Task { await feed.dismiss(first) }
        while await actions.identifiers.isEmpty {
            await Task.yield()
        }
        #expect(feed.pendingDismissalIdentifiers == ["A"])
        await feed.dismiss(second)
        await actions.finish(with: .accepted)
        await firstRequest.value

        #expect(await actions.identifiers == ["A"])
        #expect(feed.notifications == [second])
        #expect(feed.pendingDismissalIdentifiers.isEmpty)
    }

    @Test("a later authoritative refresh clears a stale dismissal error after the row disappears")
    func refreshClearsResolvedError() async throws {
        let (defaults, suiteName) = try Self.defaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = Self.notification("A")
        let initial = Self.snapshot([first], deliveredIdentifiers: ["A"])
        let actions = ActionRecorder(results: ["A": .failed])
        let reads = SnapshotRecorder(snapshots: [Self.snapshot([], deliveredIdentifiers: [])])
        let feed = NotificationFeed(
            preset: initial,
            defaults: defaults,
            readOperation: { await reads.read() },
            dismissOperation: { await actions.perform($0) }
        )

        await feed.dismiss(first)
        #expect(feed.dismissalError != nil)
        await feed.refresh()

        #expect(feed.notifications.isEmpty)
        #expect(feed.dismissalError == nil)
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
