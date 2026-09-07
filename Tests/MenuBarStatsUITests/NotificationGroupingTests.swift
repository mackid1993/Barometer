import Foundation
import SystemSources
import Testing
@testable import MenuBarStatsUI

@Suite("Notification application grouping")
struct NotificationGroupingTests {
    @Test("groups and rows are ordered by their latest notification")
    func newestFirst() throws {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let notifications = [
            Self.notification("a-old", application: "com.example.Alpha", date: start.addingTimeInterval(10)),
            Self.notification("b-new", application: "com.example.Beta", date: start.addingTimeInterval(40)),
            Self.notification("a-new", application: "com.example.alpha", date: start.addingTimeInterval(30)),
            Self.notification("b-old", application: "com.example.Beta", date: start.addingTimeInterval(20)),
        ]

        let groups = NotificationGrouping.groups(notifications)
        #expect(groups.map(\.id) == ["com.example.beta", "com.example.alpha"])
        #expect(groups[0].notifications.map(\.id) == ["b-new", "b-old"])
        #expect(groups[1].notifications.map(\.id) == ["a-new", "a-old"])
        #expect(groups[0].latest.id == "b-new")
    }

    @Test("daemon and application identifiers share one stable group")
    func canonicalApplicationIdentity() throws {
        let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let notifications = [
            Self.notification(
                "system",
                application: "_SYSTEM_CENTER_:com.apple.systempreferences",
                date: date.addingTimeInterval(1)
            ),
            Self.notification("application", application: "com.apple.systempreferences", date: date),
        ]

        let group = try #require(NotificationGrouping.groups(notifications).only)
        #expect(group.id == "com.apple.systempreferences")
        #expect(group.applicationIdentifier == "com.apple.systempreferences")
        #expect(group.notifications.map(\.id) == ["system", "application"])
    }

    @Test("grouping preserves every notification beyond one hundred rows")
    func preservesFullList() {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let notifications = (0..<150).map { index in
            Self.notification(
                "notification-\(index)",
                application: "com.example.app\(index % 4)",
                date: start.addingTimeInterval(Double(index))
            )
        }

        let groups = NotificationGrouping.groups(notifications)
        #expect(groups.count == 4)
        #expect(groups.flatMap(\.notifications).count == 150)
        #expect(Set(groups.flatMap(\.notifications).map(\.id)) == Set(notifications.map(\.id)))
        #expect(groups.allSatisfy { !$0.notifications.isEmpty })
        #expect(groups.map(\.latest.id) == [
            "notification-149", "notification-148", "notification-147", "notification-146",
        ])
    }

    @Test("equal dates retain the source order")
    func stableTieOrder() throws {
        let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let notifications = [
            Self.notification("first", application: "com.example.app", date: date),
            Self.notification("second", application: "com.example.app", date: date),
        ]

        let group = try #require(NotificationGrouping.groups(notifications).only)
        #expect(group.notifications.map(\.id) == ["first", "second"])
    }

    private static func notification(_ id: String, application: String, date: Date) -> DeliveredNotification {
        DeliveredNotification(
            id: id,
            applicationIdentifier: application,
            title: id,
            subtitle: nil,
            body: nil,
            date: date
        )
    }
}

private extension Collection {
    var only: Element? {
        count == 1 ? first : nil
    }
}
