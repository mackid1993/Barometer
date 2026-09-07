import Foundation
import Observation
import SystemSources

/// Observable Notification Center list shown by the Time dropdown.
///
/// The list is read when the dropdown opens and again whenever Notification Center's database
/// changes while the dropdown stays open. Nothing runs while the dropdown is closed.
///
/// macOS gives another application no way to dismiss a notification, so clearing here hides rows
/// from Barometer's list only. Dismissed identifiers persist and are pruned as soon as Notification
/// Center itself no longer holds them, so the set never grows past what the system still shows.
@MainActor
@Observable
public final class NotificationFeed {
    /// Latest read, or nil before the first one.
    public private(set) var snapshot: NotificationSnapshot?

    /// Whether the feed is currently watching the database for changes.
    public private(set) var isWatching = false

    /// Identifiers the user cleared in Barometer that Notification Center still holds.
    public private(set) var dismissedIdentifiers: Set<String>

    /// Defaults key holding the dismissed identifiers.
    public static let dismissedDefaultsKey = "Barometer.DismissedNotifications"

    @ObservationIgnored private let source: NotificationCenterSource
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var watchers: [DispatchSourceFileSystemObject] = []
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?
    @ObservationIgnored private var refreshGeneration = 0

    /// Debounce applied to bursts of database writes.
    static let refreshDelay: Duration = .milliseconds(250)

    /// Creates a feed over the real database by default.
    public init(source: NotificationCenterSource = NotificationCenterSource(), defaults: UserDefaults = .standard) {
        self.source = source
        self.defaults = defaults
        dismissedIdentifiers = Set(defaults.stringArray(forKey: Self.dismissedDefaultsKey) ?? [])
    }

    /// Creates a feed that already holds a list and never reads a database, for previews and screen tests.
    public init(preset: NotificationSnapshot, defaults: UserDefaults = .standard) {
        source = NotificationCenterSource(databaseURL: URL(fileURLWithPath: "/dev/null/barometer-preset"))
        self.defaults = defaults
        dismissedIdentifiers = Set(defaults.stringArray(forKey: Self.dismissedDefaultsKey) ?? [])
        snapshot = preset
        pruneDismissed()
    }

    /// The list after the user's clears.
    public var notifications: [DeliveredNotification] {
        (snapshot?.notifications ?? []).filter { !dismissedIdentifiers.contains($0.id) }
    }

    /// Hides one notification from Barometer's list.
    public func dismiss(_ notification: DeliveredNotification) {
        dismissedIdentifiers.insert(notification.id)
        saveDismissed()
    }

    /// Hides every listed notification from Barometer's list.
    public func clearAll() {
        dismissedIdentifiers.formUnion(notifications.map(\.id))
        saveDismissed()
    }

    /// Reads the list now.
    public func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        let snapshot = await source.read()
        guard generation == refreshGeneration else { return }
        self.snapshot = snapshot
        pruneDismissed()
    }

    /// Reads the list and follows database changes until `stop()` is called.
    public func start() async {
        await refresh()
        guard !isWatching else { return }
        isWatching = true
        for url in await source.watchedURLs {
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

    /// Stops following database changes and drops the list so nothing stays resident.
    public func stop() {
        isWatching = false
        pendingRefresh?.cancel()
        pendingRefresh = nil
        refreshGeneration += 1
        for watcher in watchers { watcher.cancel() }
        watchers.removeAll()
    }

    /// Forgets clears for notifications the system no longer holds, once a successful read says so.
    private func pruneDismissed() {
        guard let snapshot, snapshot.access == .available else { return }
        let present = Set(snapshot.notifications.map(\.id))
        let pruned = dismissedIdentifiers.intersection(present)
        guard pruned != dismissedIdentifiers else { return }
        dismissedIdentifiers = pruned
        saveDismissed()
    }

    private func saveDismissed() {
        defaults.set(Array(dismissedIdentifiers).sorted(), forKey: Self.dismissedDefaultsKey)
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
