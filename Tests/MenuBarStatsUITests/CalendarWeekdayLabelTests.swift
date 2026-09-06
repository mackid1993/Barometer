import Darwin
import Foundation
import MenuBarStatsCore
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

        #expect(items.count == 39)
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
    }

    @Test("Calendar navigation crosses weeks and months without retaining month grids")
    func calendarNavigationIsBounded() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 5)))
        var navigation = CalendarNavigation(selectedDate: start)

        navigation.moveWeeks(1, calendar: calendar)
        #expect(calendar.dateComponents([.year, .month, .day], from: navigation.selectedDate)
            == DateComponents(year: 2026, month: 9, day: 12))
        navigation.moveWeeks(3, calendar: calendar)
        #expect(calendar.dateComponents([.year, .month, .day], from: navigation.selectedDate)
            == DateComponents(year: 2026, month: 10, day: 3))
        navigation.moveMonths(-1, calendar: calendar)
        #expect(calendar.dateComponents([.year, .month, .day], from: navigation.selectedDate)
            == DateComponents(year: 2026, month: 9, day: 3))
        navigation.select(day: 30, calendar: calendar)
        #expect(calendar.component(.day, from: navigation.selectedDate) == 30)

        let startCPU = processCPUTime()
        for _ in 0..<10_000 {
            navigation.moveWeeks(1, calendar: calendar)
            navigation.moveWeeks(-1, calendar: calendar)
        }
        let consumedCPU = processCPUTime() - startCPU
        #expect(calendar.component(.day, from: navigation.selectedDate) == 30)
        #expect(consumedCPU < 0.25, "20,000 navigation steps consumed \(consumedCPU) seconds of CPU time")
    }

    @Test("Month navigation clamps dates that do not exist")
    func monthNavigationClampsDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let january = try #require(calendar.date(from: DateComponents(year: 2027, month: 1, day: 31)))
        var navigation = CalendarNavigation(selectedDate: january)

        navigation.moveMonths(1, calendar: calendar)

        #expect(calendar.dateComponents([.year, .month, .day], from: navigation.selectedDate)
            == DateComponents(year: 2027, month: 2, day: 28))
        navigation.reset(to: january)
        #expect(navigation.selectedDate == january)
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
        #expect(calendar.dateComponents([.year, .month, .day], from: navigation.selectedDate)
            == DateComponents(year: 2026, month: 2, day: 28))
        navigation.select(year: 2031, calendar: calendar)
        #expect(calendar.dateComponents([.year, .month, .day], from: navigation.selectedDate)
            == DateComponents(year: 2031, month: 2, day: 28))
        navigation.moveYears(-10, calendar: calendar)
        #expect(calendar.component(.year, from: navigation.selectedDate) == 2021)
    }

    @Test("Ordinary vertical scrolling browses months and Option-scroll browses weeks")
    func verticalScrollBehavior() {
        #expect(CalendarBrowseAction.vertical(steps: -1, optionKey: false) == .months(-1))
        #expect(CalendarBrowseAction.vertical(steps: 1, optionKey: false) == .months(1))
        #expect(CalendarBrowseAction.vertical(steps: -1, optionKey: true) == .weeks(-1))
        #expect(CalendarBrowseAction.vertical(steps: 1, optionKey: true) == .weeks(1))
    }

    private func processCPUTime() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
        let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
        return user + system
    }
}
