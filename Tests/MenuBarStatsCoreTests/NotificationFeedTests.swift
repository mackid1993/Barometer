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

    @Test("clearing hides rows locally, persists, and forgets rows the system no longer holds")
    func clearsAndPrunes() throws {
        let suiteName = "NotificationFeedTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = Self.notification("A")
        let second = Self.notification("B")
        let feed = NotificationFeed(
            preset: NotificationSnapshot(access: .available, notifications: [first, second]), defaults: defaults)

        #expect(feed.notifications.map(\.id) == ["A", "B"])
        feed.dismiss(first)
        #expect(feed.notifications.map(\.id) == ["B"])
        feed.clearAll()
        #expect(feed.notifications.isEmpty)
        #expect(defaults.stringArray(forKey: NotificationFeed.dismissedDefaultsKey) == ["A", "B"])

        // A later feed over a list where the system only still holds B keeps that clear and drops A.
        let later = NotificationFeed(
            preset: NotificationSnapshot(access: .available, notifications: [second]), defaults: defaults)
        #expect(later.notifications.isEmpty)
        #expect(later.dismissedIdentifiers == ["B"])
        #expect(defaults.stringArray(forKey: NotificationFeed.dismissedDefaultsKey) == ["B"])

        // A failed read never prunes: the clears survive a missing grant.
        let blocked = NotificationFeed(
            preset: NotificationSnapshot(access: .fullDiskAccessRequired, notifications: []), defaults: defaults)
        #expect(blocked.dismissedIdentifiers == ["B"])
    }
}
