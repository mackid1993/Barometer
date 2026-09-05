import Foundation
import SystemSources
@testable import MenuBarStatsCore
import Testing

@Suite("TimeTests")
struct TimeTests {
    @Test("token engine renders deterministic local fields")
    func tokenRendering() throws {
        let date = Date(timeIntervalSince1970: 1_704_110_400)
        let zone = try #require(TimeZone(identifier: "UTC"))
        let rendered = TimeFormatEngine.render(
            date: date,
            timeZone: zone,
            template: "{weekday} {date} {time24} W{week} D{day} {zone}",
            showsSeconds: false,
            locale: Locale(identifier: "en_US_POSIX")
        )

        let abbreviation = zone.abbreviation(for: date) ?? zone.identifier
        #expect(rendered == "Mon Jan 1 12:00 W01 D001 \(abbreviation)")
    }

    @Test("seconds preference controls the default clock token")
    func secondsFormatting() throws {
        let date = Date(timeIntervalSince1970: 1_704_110_400)
        let zone = try #require(TimeZone(identifier: "America/New_York"))

        #expect(normalizedWhitespace(TimeFormatEngine.render(
            date: date,
            timeZone: zone,
            template: "{time}",
            showsSeconds: false,
            locale: Locale(identifier: "en_US_POSIX")
        )) == "7:00 AM")
        #expect(normalizedWhitespace(TimeFormatEngine.render(
            date: date,
            timeZone: zone,
            template: "{time}",
            showsSeconds: true,
            locale: Locale(identifier: "en_US_POSIX")
        )) == "7:00:00 AM")
    }

    @Test("time settings normalize world clock identifiers")
    func worldClockNormalization() {
        var settings = TimeSettings(worldClockIdentifiers: ["UTC", "UTC", "Bad/Zone", "Asia/Tokyo"])
        settings.normalize()

        #expect(settings.worldClockIdentifiers == ["UTC", "Asia/Tokyo"])
    }

    @Test("minute scheduling aligns to the next wall-clock minute")
    func minuteAlignment() {
        let date = Date(timeIntervalSinceReferenceDate: 3_612.25)
        #expect(abs(TimeMonitor.secondsUntilNextMinute(date: date) - 47.75) < 0.001)
    }

    @Test("seconds ticks reuse Calendar data for one minute")
    func secondsTicksReuseCalendarData() async {
        let source = CountingCalendarSource()
        let monitor = TimeMonitor(showsSeconds: true, calendarSource: source)
        await monitor.setCalendarConfiguration(isEnabled: true, count: 5)
        let start = Date(timeIntervalSinceReferenceDate: 10_000)

        let first = await monitor.sample(at: start)
        let second = await monitor.sample(at: start.addingTimeInterval(1))
        let beforeRefresh = await monitor.sample(at: start.addingTimeInterval(59))
        let refreshed = await monitor.sample(at: start.addingTimeInterval(60))
        let counts = await source.counts

        #expect(first.timestamp == start)
        #expect(second.timestamp == start.addingTimeInterval(1))
        #expect(beforeRefresh.timestamp == start.addingTimeInterval(59))
        #expect(refreshed.timestamp == start.addingTimeInterval(60))
        #expect(first.upcomingEvents == second.upcomingEvents)
        #expect(counts.authorization == 2)
        #expect(counts.events == 2)
    }

    @Test("token expansion computes only fields present in the template")
    func tokenExpansionIsLazy() {
        var requested: [String] = []
        let result = TimeFormatEngine.replacingTokens(in: "Clock {time} {zone}") { token in
            requested.append(token)
            return token == "{time}" ? "9:41:30 AM" : "EDT"
        }

        #expect(result == "Clock 9:41:30 AM EDT")
        #expect(requested == ["{time}", "{zone}"])
    }

    private func normalizedWhitespace(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
    }
}

private actor CountingCalendarSource: CalendarEventProviding {
    private var authorizationCount = 0
    private var eventCount = 0

    var authorizationState: CalendarAuthorizationState {
        authorizationCount += 1
        return .fullAccess
    }

    var counts: (authorization: Int, events: Int) {
        (authorizationCount, eventCount)
    }

    func requestFullAccess() async throws -> CalendarAuthorizationState {
        .fullAccess
    }

    func events(from date: Date, limit: Int) -> [CalendarEventSnapshot] {
        eventCount += 1
        return [
            CalendarEventSnapshot(
                id: "event",
                title: "Event",
                startDate: date.addingTimeInterval(3_600),
                endDate: date.addingTimeInterval(7_200),
                isAllDay: false,
                calendarTitle: "Calendar"
            )
        ]
    }
}
