import Darwin
import Foundation
import MenuBarStatsCore
import SystemSources
import Testing
@testable import MenuBarStatsUI

@Suite("Calendar weekday labels")
struct CalendarWeekdayLabelTests {
    @Test("Duplicate short symbols keep seven stable grid identities")
    func duplicateSymbolsRemainDistinct() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.firstWeekday = 1

        let labels = CalendarWeekdayLabel.labels(for: calendar)

        #expect(labels.count == 7)
        #expect(Set(labels.map(\.id)).count == 7)
        #expect(Set(labels.map(\.symbol)).count < labels.count)
        #expect(labels.map(\.symbol) == calendar.veryShortStandaloneWeekdaySymbols)
    }

    @Test("First weekday rotates labels without changing identities")
    func respectsFirstWeekday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.firstWeekday = 2

        let labels = CalendarWeekdayLabel.labels(for: calendar)
        let symbols = calendar.veryShortStandaloneWeekdaySymbols

        #expect(labels.map(\.id) == Array(0..<7))
        #expect(labels.map(\.symbol) == Array(symbols[1...] + symbols[..<1]))
    }

    @Test("Every explicit week start maps to a distinct calendar column")
    func explicitWeekStarts() {
        let choices = CalendarWeekStart.allCases.filter { $0 != .systemDefault }

        #expect(choices.compactMap(\.firstWeekday) == Array(1...7))
        #expect(Set(choices.compactMap(\.firstWeekday)).count == 7)
    }

    @Test("September 2026 keeps its headings, leading cells, and first week distinct")
    func septemberGridRowsRemainComplete() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.firstWeekday = 1
        let items = CalendarGridItem.items(
            weekdayLabels: CalendarWeekdayLabel.labels(for: calendar),
            leadingCellCount: 2,
            days: 1..<31
        )

        #expect(items.count == 49)
        #expect(Set(items.map(\.id)).count == items.count)
        #expect(Array(items.prefix(7)) == [
            .weekday(column: 0, symbol: "S"),
            .weekday(column: 1, symbol: "M"),
            .weekday(column: 2, symbol: "T"),
            .weekday(column: 3, symbol: "W"),
            .weekday(column: 4, symbol: "T"),
            .weekday(column: 5, symbol: "F"),
            .weekday(column: 6, symbol: "S"),
        ])
        #expect(Array(items[7...13]) == [
            .leadingCell(column: 0),
            .leadingCell(column: 1),
            .day(1),
            .day(2),
            .day(3),
            .day(4),
            .day(5),
        ])
        #expect(Array(items[14...20]) == [
            .day(6),
            .day(7),
            .day(8),
            .day(9),
            .day(10),
            .day(11),
            .day(12),
        ])
        #expect(Array(items.suffix(10)) == (0..<10).map(CalendarGridItem.trailingCell(column:)))
    }

    @Test("Every month reserves six complete week rows")
    func everyMonthHasStableGridHeight() {
        let labels = (0..<7).map { CalendarWeekdayLabel(id: $0, symbol: String($0)) }
        for leadingCellCount in 0...6 {
            for dayCount in 28...31 {
                let items = CalendarGridItem.items(
                    weekdayLabels: labels,
                    leadingCellCount: leadingCellCount,
                    days: 1..<(dayCount + 1)
                )
                #expect(items.count == 49)
                #expect(Set(items.map(\.id)).count == 49)
            }
        }
    }

    @Test("Calendar arrows cross months without retaining month grids")
    func calendarNavigationIsBounded() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 5)))
        var navigation = CalendarNavigation(selectedDate: start)

        navigation.moveMonths(1, calendar: calendar)
        #expect(calendar.dateComponents([.year, .month, .day], from: navigation.visibleDate)
            == DateComponents(year: 2026, month: 10, day: 5))
        navigation.moveMonths(3, calendar: calendar)
        #expect(calendar.dateComponents([.year, .month, .day], from: navigation.visibleDate)
            == DateComponents(year: 2027, month: 1, day: 5))
        navigation.moveMonths(-4, calendar: calendar)
        #expect(calendar.dateComponents([.year, .month, .day], from: navigation.visibleDate)
            == DateComponents(year: 2026, month: 9, day: 5))

        let startCPU = processCPUTime()
        for _ in 0..<10_000 {
            navigation.moveMonths(1, calendar: calendar)
            navigation.moveMonths(-1, calendar: calendar)
        }
        let consumedCPU = processCPUTime() - startCPU
        #expect(calendar.dateComponents([.year, .month, .day], from: navigation.visibleDate)
            == DateComponents(year: 2026, month: 9, day: 5))
        #expect(consumedCPU < 0.25, "20,000 month steps consumed \(consumedCPU) seconds of CPU time")
    }

    @Test("Month navigation clamps dates that do not exist")
    func monthNavigationClampsDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let january = try #require(calendar.date(from: DateComponents(year: 2027, month: 1, day: 31)))
        var navigation = CalendarNavigation(selectedDate: january)

        navigation.moveMonths(1, calendar: calendar)

        #expect(calendar.dateComponents([.year, .month, .day], from: navigation.visibleDate)
            == DateComponents(year: 2027, month: 2, day: 28))
        navigation.reset(to: january)
        #expect(navigation.visibleDate == january)
    }

    @Test("Calendar drill-out navigates month, year, and decade levels")
    func drillOutNavigation() throws {
        var mode = CalendarDisplayMode.month
        mode.zoomOut()
        #expect(mode == .year)
        mode.zoomOut()
        #expect(mode == .decade)
        mode.zoomOut()
        #expect(mode == .decade)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 30)))
        var navigation = CalendarNavigation(selectedDate: start)
        navigation.select(month: 2, calendar: calendar)
        #expect(calendar.dateComponents([.year, .month, .day], from: navigation.visibleDate)
            == DateComponents(year: 2026, month: 2, day: 28))
        navigation.select(year: 2031, calendar: calendar)
        #expect(calendar.dateComponents([.year, .month, .day], from: navigation.visibleDate)
            == DateComponents(year: 2031, month: 2, day: 28))
        navigation.moveYears(-10, calendar: calendar)
        #expect(calendar.component(.year, from: navigation.visibleDate) == 2021)
    }

    @Test("Upcoming event rows show an approachable weekday and date")
    func eventRowsShowDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let start = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 7,
            hour: 9,
            minute: 30
        )))
        let timed = CalendarEventSnapshot(
            id: "timed",
            title: "Planning",
            startDate: start,
            endDate: start.addingTimeInterval(3_600),
            isAllDay: false,
            calendarTitle: "Work"
        )
        let allDay = CalendarEventSnapshot(
            id: "all-day",
            title: "Holiday",
            startDate: start,
            endDate: start.addingTimeInterval(86_400),
            isAllDay: true,
            calendarTitle: "Home"
        )
        let locale = Locale(identifier: "en_US_POSIX")

        #expect(normalizedWhitespace(
            CalendarEventScheduleFormatter.string(for: timed, locale: locale, timeZone: .gmt)
        ) == "Mon, Sep 7 • 9:30 AM")
        #expect(CalendarEventScheduleFormatter.string(for: allDay, locale: locale, timeZone: .gmt)
            == "Mon, Sep 7 • All day")
    }

    /// CPU time consumed by the calling thread.
    ///
    /// `getrusage(RUSAGE_SELF)` reports the whole process, so a parallel suite doing real work in
    /// another thread inflated this budget and failed the assertion on a slower shared runner. The
    /// measurement must cover only the loop under test, which stays on one thread throughout.
    private func processCPUTime() -> Double {
        var elapsed = timespec()
        guard clock_gettime(CLOCK_THREAD_CPUTIME_ID, &elapsed) == 0 else { return 0 }
        return Double(elapsed.tv_sec) + Double(elapsed.tv_nsec) / 1_000_000_000
    }

    private func normalizedWhitespace(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
    }
}
