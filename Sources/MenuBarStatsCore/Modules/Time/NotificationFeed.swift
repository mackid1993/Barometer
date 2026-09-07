import Foundation
import Observation
import SystemSources

/// Observable Notification Center list shown by the Time dropdown.
///
/// The list is read when the dropdown opens and again whenever Notification Center's database
/// changes while the dropdown stays open. Passive reads stop when the dropdown closes; a clear
/// already requested by the user finishes its bounded confirmation reads.
///
/// Clear requests go through macOS, then an authoritative database read verifies that each UUID
/// disappeared. A row remains visible when the action fails or its result cannot be verified.
@MainActor
@Observable
public final class NotificationFeed {
    /// Latest read, or nil before the first one.
    public private(set) var snapshot: NotificationSnapshot?

    /// Whether the feed is currently watching the database for changes.
    public private(set) var isWatching = false

    /// UUIDs covered by the clear request currently being processed.
    public private(set) var pendingDismissalIdentifiers: Set<String> = []

    /// An explanation when macOS did not clear a requested notification or Barometer could not verify it.
    public private(set) var dismissalError: String?

    /// Legacy defaults key used by builds that hid cleared notifications only inside Barometer.
    public static let dismissedDefaultsKey = "Barometer.DismissedNotifications"

    @ObservationIgnored private let source: NotificationCenterSource
    @ObservationIgnored private let readOperation: @Sendable () async -> NotificationSnapshot
    @ObservationIgnored private let dismissOperation:
        @Sendable (DeliveredNotification) async -> NotificationSystemActionResult
    @ObservationIgnored private let dismissalVerificationDelays: [Duration]
    @ObservationIgnored private var dismissalErrorIdentifiers: Set<String> = []
    @ObservationIgnored private var watchers: [DispatchSourceFileSystemObject] = []
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?
    @ObservationIgnored private var reconciliationTask: Task<Void, Never>?
    @ObservationIgnored private var refreshGeneration = 0
    @ObservationIgnored private var dismissalGeneration = 0
    @ObservationIgnored private var watchGeneration = 0
    @ObservationIgnored private var retainedNotifications: [DeliveredNotification] = []

    /// Debounce applied to bursts of database writes.
    static let refreshDelay: Duration = .milliseconds(250)

    /// Creates a feed over the real database and macOS notification action bridge by default.
    public init(
        source: NotificationCenterSource = NotificationCenterSource(),
        actionBridge: NotificationCenterActionBridge = NotificationCenterActionBridge(),
        defaults: UserDefaults = .standard
    ) {
        self.source = source
        readOperation = { await source.read() }
        dismissOperation = { await actionBridge.perform(.dismiss, for: $0) }
        dismissalVerificationDelays = [.milliseconds(150), .milliseconds(350), .seconds(1)]
        Self.restoreLegacyDismissals(defaults: defaults)
    }

    /// Creates a feed that already holds a list and never reads a database, for previews and screen tests.
    public init(preset: NotificationSnapshot, defaults: UserDefaults = .standard) {
        source = NotificationCenterSource(databaseURL: URL(fileURLWithPath: "/dev/null/barometer-preset"))
        readOperation = { preset }
        dismissOperation = { _ in .unavailable }
        dismissalVerificationDelays = []
        snapshot = preset
        retainedNotifications = preset.notifications
        Self.restoreLegacyDismissals(defaults: defaults)
    }

    /// Creates a deterministic feed with injected system operations for tests.
    init(
        preset: NotificationSnapshot,
        defaults: UserDefaults,
        readOperation: @escaping @Sendable () async -> NotificationSnapshot,
        dismissOperation: @escaping @Sendable (DeliveredNotification) async -> NotificationSystemActionResult,
        dismissalVerificationDelays: [Duration] = []
    ) {
        source = NotificationCenterSource(databaseURL: URL(fileURLWithPath: "/dev/null/barometer-test"))
        self.readOperation = readOperation
        self.dismissOperation = dismissOperation
        self.dismissalVerificationDelays = dismissalVerificationDelays
        snapshot = preset
        retainedNotifications = preset.notifications
        Self.restoreLegacyDismissals(defaults: defaults)
    }

    /// The notifications currently reported by macOS.
    public var notifications: [DeliveredNotification] {
        snapshot?.notifications ?? []
    }

    /// Whether a clear request is in flight.
    public var isDismissing: Bool {
        !pendingDismissalIdentifiers.isEmpty
    }

    /// Asks macOS to clear one notification and verifies the result before removing its row.
    public func dismiss(_ notification: DeliveredNotification) async {
        await dismiss([notification])
    }

    /// Asks macOS to clear exactly the supplied listed notifications and verifies the results.
    ///
    /// The caller supplies the visible rows so this never clears notifications outside the list the
    /// user chose to act on. A second request is ignored while the first request is in flight.
    public func dismiss(_ requestedNotifications: [DeliveredNotification]) async {
        guard pendingDismissalIdentifiers.isEmpty else { return }
        let listedIdentifiers = Set(notifications.map(\.id))
        var seen: Set<String> = []
        let requested = requestedNotifications.filter {
            listedIdentifiers.contains($0.id) && seen.insert($0.id).inserted
        }
        guard !requested.isEmpty else { return }

        let requestedIdentifiers = Set(requested.map(\.id))
        dismissalGeneration += 1
        let operationGeneration = dismissalGeneration
        refreshGeneration += 1
        pendingDismissalIdentifiers = requestedIdentifiers
        dismissalError = nil
        dismissalErrorIdentifiers = []

        var acceptedIdentifiers: Set<String> = []
        var unavailableIdentifiers: Set<String> = []
        var failedIdentifiers: Set<String> = []
        for notification in requested {
            switch await dismissOperation(notification) {
            case .accepted:
                acceptedIdentifiers.insert(notification.id)
            case .unavailable:
                unavailableIdentifiers.insert(notification.id)
            case .failed:
                failedIdentifiers.insert(notification.id)
            }
            guard operationGeneration == dismissalGeneration else {
                pendingDismissalIdentifiers = []
                return
            }
        }

        let attemptedIdentifiers = acceptedIdentifiers.union(failedIdentifiers)
        var verifiedRemaining = requestedIdentifiers
        if !attemptedIdentifiers.isEmpty {
            var verifiedIdentifiers: Set<String>?
            for delay in [Duration.zero] + dismissalVerificationDelays {
                if delay > .zero {
                    try? await Task.sleep(for: delay)
                }
                guard operationGeneration == dismissalGeneration, !Task.isCancelled else {
                    pendingDismissalIdentifiers = []
                    return
                }
                refreshGeneration += 1
                let generation = refreshGeneration
                let refreshed = await readOperation()
                guard operationGeneration == dismissalGeneration, !Task.isCancelled else {
                    pendingDismissalIdentifiers = []
                    return
                }
                guard generation == refreshGeneration else { continue }
                guard refreshed.access == .available,
                      let deliveredIdentifiers = refreshed.deliveredNotificationIdentifiers
                else {
                    continue
                }
                verifiedIdentifiers = deliveredIdentifiers
                apply(refreshed, preserving: requestedIdentifiers)
                if attemptedIdentifiers.isDisjoint(with: deliveredIdentifiers) { break }
            }
            if let verifiedIdentifiers {
                verifiedRemaining = requestedIdentifiers.intersection(verifiedIdentifiers)
            } else {
                dismissalError = "Barometer asked macOS to clear the notifications but could not verify the result. "
                    + "They remain listed; refresh or clear them in Notification Center."
                dismissalErrorIdentifiers = requestedIdentifiers
                pendingDismissalIdentifiers = []
                return
            }
        }

        let acceptedButPresent = acceptedIdentifiers.intersection(verifiedRemaining)
        let failedButPresent = failedIdentifiers.intersection(verifiedRemaining)
        let unresolved = acceptedButPresent.union(unavailableIdentifiers).union(failedButPresent)
        dismissalErrorIdentifiers = unresolved
        if !unavailableIdentifiers.isEmpty {
            dismissalError = "Barometer cannot clear some notifications through macOS right now. "
                + "Clear them in Notification Center."
        } else if !failedButPresent.isEmpty {
            dismissalError = "macOS did not clear some notifications. Try again, or clear them in Notification Center."
        } else if !acceptedButPresent.isEmpty {
            dismissalError = "macOS accepted the clear request, but some notifications are still present. "
                + "Try again, or clear them in Notification Center."
        }
        pendingDismissalIdentifiers = []
    }

    /// Reads the list now.
    public func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        let refreshed = await readOperation()
        guard generation == refreshGeneration else { return }
        apply(refreshed, preserving: pendingDismissalIdentifiers.union(dismissalErrorIdentifiers))
    }

    /// Reads the list and follows database changes until `stop()` is called.
    public func start() async {
        watchGeneration += 1
        let generation = watchGeneration
        await refresh()
        guard generation == watchGeneration, !Task.isCancelled, !isWatching else { return }
        let urls = await source.watchedURLs
        guard generation == watchGeneration, !Task.isCancelled else { return }
        isWatching = true
        // Directory/WAL replacement and a temporarily missing file can leave a watcher stale.
        // Reconcile while open even if a file-system event is missed.
        reconciliationTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                guard let self, self.isWatching else { return }
                await self.refresh()
            }
        }
        for url in urls {
            let descriptor = open(url.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let watcher = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .extend, .delete, .rename],
                queue: .main
            )
            watcher.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.scheduleRefresh() }
            }
            watcher.setCancelHandler { close(descriptor) }
            watcher.resume()
            watchers.append(watcher)
        }
    }

    /// Stops following database changes and cancels a pending debounced read.
    public func stop() {
        watchGeneration += 1
        isWatching = false
        pendingRefresh?.cancel()
        pendingRefresh = nil
        reconciliationTask?.cancel()
        reconciliationTask = nil
        refreshGeneration += 1
        // A clear the user already requested must finish even if the dropdown closes.
        // Only passive watching stops; the bounded confirmation reads belong to that action.
        for watcher in watchers { watcher.cancel() }
        watchers.removeAll()
    }

    private func apply(_ refreshed: NotificationSnapshot, preserving identifiers: Set<String> = []) {
        guard refreshed.access == .available else {
            // Keep the last usable records in memory even when visibility settings cannot be
            // read. Such rows stay hidden until the current exclusions can be checked again.
            var known = Dictionary(retainedNotifications.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            for notification in refreshed.notifications { known[notification.id] = notification }
            retainedNotifications = known.values.sorted { $0.date > $1.date }
            let retained = retainedNotifications.filter { notification in
                guard let hidden = refreshed.hiddenApplicationIdentifiers else { return false }
                return !hidden.contains(NotificationCenterSource.canonicalApplicationIdentifier(
                    notification.applicationIdentifier))
            }
            snapshot = NotificationSnapshot(
                access: refreshed.access,
                notifications: retained,
                readDate: snapshot?.readDate ?? refreshed.readDate,
                unavailabilityReason: refreshed.unavailabilityReason,
                hiddenApplicationIdentifiers: refreshed.hiddenApplicationIdentifiers)
            return
        }
        snapshot = snapshotByPreservingDeliveredRows(refreshed, identifiers: identifiers)
        retainedNotifications = snapshot?.notifications ?? []
        guard refreshed.access == .available,
              let deliveredIdentifiers = refreshed.deliveredNotificationIdentifiers,
              dismissalErrorIdentifiers.isDisjoint(with: deliveredIdentifiers)
        else {
            return
        }
        dismissalError = nil
        dismissalErrorIdentifiers = []
    }

    /// Keeps a requested row when it remains in the authoritative delivered set but falls outside
    /// the source's display limit. Absence from the limited row list never proves dismissal.
    private func snapshotByPreservingDeliveredRows(
        _ refreshed: NotificationSnapshot,
        identifiers: Set<String>
    ) -> NotificationSnapshot {
        guard let prior = snapshot,
              let deliveredIdentifiers = refreshed.deliveredNotificationIdentifiers,
              !identifiers.isEmpty
        else {
            return refreshed
        }
        let refreshedIdentifiers = Set(refreshed.notifications.map(\.id))
        let retained = prior.notifications.filter {
            identifiers.contains($0.id)
                && deliveredIdentifiers.contains($0.id)
                && !refreshedIdentifiers.contains($0.id)
                && !(refreshed.hiddenApplicationIdentifiers ?? []).contains(
                    NotificationCenterSource.canonicalApplicationIdentifier($0.applicationIdentifier))
        }
        guard !retained.isEmpty else { return refreshed }
        return NotificationSnapshot(
            access: refreshed.access,
            notifications: refreshed.notifications + retained,
            readDate: refreshed.readDate,
            deliveredNotificationIdentifiers: deliveredIdentifiers,
            hiddenApplicationIdentifiers: refreshed.hiddenApplicationIdentifiers
        )
    }

    /// Restores notifications hidden by older builds and removes the obsolete local-only state.
    private static func restoreLegacyDismissals(defaults: UserDefaults) {
        defaults.removeObject(forKey: dismissedDefaultsKey)
    }

    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            try? await Task.sleep(for: Self.refreshDelay)
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }
}
