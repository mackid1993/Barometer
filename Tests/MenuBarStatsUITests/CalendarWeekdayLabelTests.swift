import Foundation
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
}
