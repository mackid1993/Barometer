import Foundation
import Testing
@testable import MenuBarStatsUI

@Suite("Time notification rows")
struct TimeNotificationTests {
    @Test("notification ages read as now, minutes, hours, yesterday, then a date")
    func ages() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 15, minute: 0)))
        func age(_ seconds: TimeInterval) -> String {
            NotificationAgeFormatter.string(from: now.addingTimeInterval(-seconds), now: now, calendar: calendar)
        }
        #expect(age(5) == "now")
        #expect(age(600) == "10m")
        #expect(age(2 * 3_600) == "2h")
        #expect(age(16 * 3_600) == "Yesterday")
        #expect(age(3 * 86_400) == "Sep 4")
    }
}
