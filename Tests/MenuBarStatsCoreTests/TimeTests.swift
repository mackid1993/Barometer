import Foundation
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

    private func normalizedWhitespace(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
    }
}
