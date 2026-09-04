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

        #expect(rendered == "Mon Jan 1 13:20 W01 D001 UTC")
    }

    @Test("seconds preference controls the default clock token")
    func secondsFormatting() throws {
        let date = Date(timeIntervalSince1970: 1_704_110_400)
        let zone = try #require(TimeZone(identifier: "America/New_York"))

        #expect(TimeFormatEngine.render(
            date: date,
            timeZone: zone,
            template: "{time}",
            showsSeconds: false,
            locale: Locale(identifier: "en_US_POSIX")
        ) == "8:20 AM")
        #expect(TimeFormatEngine.render(
            date: date,
            timeZone: zone,
            template: "{time}",
            showsSeconds: true,
            locale: Locale(identifier: "en_US_POSIX")
        ) == "8:20:00 AM")
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
}
