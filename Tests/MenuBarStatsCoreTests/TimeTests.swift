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

    @Test
    func dropdownOrderAndHeightNormalize() {
        let order = TimeDropdownSection.normalizedOrder([.sun, .calendar, .sun])
        #expect(order == [.sun, .calendar, .dayEvents, .notifications, .worldClocks, .upcomingEvents])
        let settings = TimeSettings(dropdownSectionOrder: [.notifications], dropdownHeight: 5_000)
        #expect(settings.dropdownSectionOrder.first == .notifications)
        #expect(settings.dropdownSectionOrder.count == TimeDropdownSection.allCases.count)
        #expect(settings.dropdownHeight == TimeSettings.dropdownHeightRange.upperBound)
        #expect(TimeSettings().dropdownHeight == TimeSettings.defaultDropdownHeight)
    }

    @Test("dropdown seconds default off and survive persistence")
    func dropdownSecondsPersistence() throws {
        #expect(TimeSettings().showsDropdownSeconds == false)

        let encoded = try JSONEncoder().encode(TimeSettings(showsDropdownSeconds: true))
        #expect(try JSONDecoder().decode(TimeSettings.self, from: encoded).showsDropdownSeconds)

        var olderDocument = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        olderDocument.removeValue(forKey: "showsDropdownSeconds")
        let olderData = try JSONSerialization.data(withJSONObject: olderDocument)
        #expect(try JSONDecoder().decode(TimeSettings.self, from: olderData).showsDropdownSeconds == false)
    }

    @Test("Now Playing visibility defaults safely and survives persistence")
    func nowPlayingVisibilityPersistence() throws {
        #expect(TimeSettings().nowPlayingVisibility == .whenPlaying)

        let encoded = try JSONEncoder().encode(TimeSettings(nowPlayingVisibility: .always))
        #expect(try JSONDecoder().decode(TimeSettings.self, from: encoded).nowPlayingVisibility == .always)

        var olderDocument = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        olderDocument.removeValue(forKey: "nowPlayingVisibility")
        let olderData = try JSONSerialization.data(withJSONObject: olderDocument)
        #expect(try JSONDecoder().decode(TimeSettings.self, from: olderData).nowPlayingVisibility == .whenPlaying)
    }

    @Test
    func clockTextSizeStaysInsideTheMenuBarRange() {
        #expect(TimeSettings(menuBarFontSize: 30).menuBarFontSize == TimeSettings.menuBarFontSizeRange.upperBound)
        #expect(TimeSettings(menuBarFontSize: 2).menuBarFontSize == TimeSettings.menuBarFontSizeRange.lowerBound)
        #expect(TimeSettings(menuBarFontSize: nil).menuBarFontSize == nil)
        let configuration = TimeMenuBarConfiguration(template: "{time}", showsSeconds: false, usesFixedWidth: true,
                                                     fontSize: 99)
        #expect(configuration.fontSize == TimeSettings.menuBarFontSizeRange.upperBound)
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

    @Test("selecting a calendar day loads that day and preserves upcoming events")
    func selectedDayEvents() async throws {
        let source = CountingCalendarSource()
        let monitor = TimeMonitor(calendarSource: source)
        await monitor.setCalendarConfiguration(isEnabled: true, count: 5)
        let selected = Date(timeIntervalSinceReferenceDate: 200_000)
        let initial = await monitor.sample(at: selected.addingTimeInterval(-86_400))

        let selection = await monitor.selectCalendarDate(selected)
        let nextTick = await monitor.sample(at: selection.timestamp.addingTimeInterval(1))

        let calendar = Calendar.current
        let loadedDate = try #require(selection.selectedCalendarDate)
        #expect(calendar.isDate(loadedDate, inSameDayAs: selected))
        #expect(selection.selectedDayEvents.map(\.id) == ["event"])
        #expect(selection.upcomingEvents == initial.upcomingEvents)
        #expect(nextTick.selectedCalendarDate == selection.selectedCalendarDate)
        #expect(nextTick.selectedDayEvents == selection.selectedDayEvents)

        await monitor.setCalendarConfiguration(isEnabled: false, count: 5)
        let disabled = await monitor.sample(at: nextTick.timestamp.addingTimeInterval(1))
        #expect(disabled.selectedCalendarDate == nil)
        #expect(disabled.selectedDayEvents.isEmpty)
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
