import Foundation
import Testing
@testable import MenuBarStatsCore

@Suite("WeatherDayDetailsTests")
struct WeatherDayDetailsTests {
    @Test("Days use the forecast time zone and exclude the next midnight")
    func dayBoundaries() throws {
        let zone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let date = try instant("2026-09-04T07:00:00Z")
        let hours = [-1.0, 0, 12, 23, 24].map { hour(date.addingTimeInterval($0 * 3_600)) }
        let details = WeatherDayDetails(day: day(date), hourly: hours.reversed(), timeZone: zone)
        #expect(details.hourly.map(\.time) == [0.0, 12, 23].map { date.addingTimeInterval($0 * 3_600) })
    }

    @Test("Spring and fall daylight saving days retain 23 and 25 hours", arguments: [
        ("2026-03-08T05:00:00Z", 23), ("2026-11-01T04:00:00Z", 25)
    ])
    func daylightSaving(_ input: (String, Int)) throws {
        let date = try instant(input.0)
        let zone = try #require(TimeZone(identifier: "America/New_York"))
        let hours = (-1...26).map { hour(date.addingTimeInterval(Double($0) * 3_600)) }
        let details = WeatherDayDetails(day: day(date), hourly: hours, timeZone: zone)
        #expect(details.hourly.count == input.1)
        #expect(details.hourly.first?.time == date)
    }

    @Test("Missing hourly and solar data remains unavailable")
    func missingData() {
        let details = WeatherDayDetails(day: day(Date()), hourly: [], timeZone: .gmt)
        #expect(details.hourly.isEmpty)
        #expect(details.daylightDuration == nil)
        #expect(details.day.high == nil)
        #expect(details.day.precipitationProbability == nil)
    }

    @Test("Sunrise and sunset yield actual daylight duration")
    func daylight() {
        let date = Date(timeIntervalSince1970: 0)
        let details = WeatherDayDetails(
            day: day(date, sunrise: date, sunset: date.addingTimeInterval(43_200)), hourly: [], timeZone: .gmt)
        #expect(details.daylightDuration == 43_200)
        let invalid = WeatherDayDetails(
            day: day(date, sunrise: date, sunset: date.addingTimeInterval(-1)), hourly: [], timeZone: .gmt)
        #expect(invalid.daylightDuration == nil)
    }

    @Test("Lunar phase and illumination use selected-day local noon")
    func localMoon() throws {
        let date = try instant("2026-09-04T07:00:00Z")
        let noon = try instant("2026-09-04T19:00:00Z")
        let zone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let details = WeatherDayDetails(day: day(date), hourly: [], timeZone: zone)
        #expect(details.moonPhase == MoonPhase.calculate(for: noon))
        #expect(details.moonIllumination == MoonPhase.illuminationFraction(for: noon))
    }

    @Test("Illumination agrees with all eight phase stages", arguments: Array(0..<8))
    func phases(_ stage: Int) {
        let date = Date(timeIntervalSince1970: 947_182_440 + Double(stage) / 8 * 29.530_588_853 * 86_400)
        #expect(MoonPhase.calculate(for: date) == MoonPhase.allCases[stage])
        #expect(abs(MoonPhase.illuminationFraction(for: date) - (1 - cos(Double(stage) * .pi / 4)) / 2) < 0.000_001)
        #expect((0...1).contains(MoonPhase.illuminationFraction(for: date)))
    }

    @Test("Provider moon phase and polar daylight take precedence over estimates")
    func providerMoon() {
        let date = Date(timeIntervalSince1970: 0)
        let provider = DailyWeatherDetails(values: [.moonPhase: 0.5, .daylightDuration: 86_400])
        let details = WeatherDayDetails(day: day(date, details: provider), hourly: [], timeZone: .gmt)
        #expect(details.moonPhase == .fullMoon)
        #expect(details.moonIllumination == 1)
        #expect(!details.usesEstimatedMoonPhase)
        #expect(details.daylightDuration == 86_400)
    }

    @Test("Out-of-range provider moon phases fall back to the selected date")
    func invalidProviderMoon() {
        let provider = DailyWeatherDetails(values: [.moonPhase: 7])
        let details = WeatherDayDetails(day: day(Date(), details: provider), hourly: [], timeZone: .gmt)
        #expect(details.usesEstimatedMoonPhase)
        #expect((0...1).contains(details.moonIllumination))
    }

    private func instant(_ value: String) throws -> Date { try #require(ISO8601DateFormatter().date(from: value)) }

    private func day(
        _ date: Date, sunrise: Date? = nil, sunset: Date? = nil, details: DailyWeatherDetails? = nil
    ) -> DailyPoint {
        DailyPoint(date: date, code: nil, high: nil, low: nil, apparentHigh: nil, apparentLow: nil,
                   sunrise: sunrise, sunset: sunset, uvIndexMax: nil, precipitation: nil,
                   precipitationProbability: nil, windSpeedMax: nil, windGustsMax: nil, details: details)
    }

    private func hour(_ time: Date) -> HourlyPoint {
        HourlyPoint(time: time, temperature: nil, apparentTemperature: nil, precipitationProbability: nil,
                    precipitation: nil, code: nil, windSpeed: nil, windDirection: nil, uvIndex: nil,
                    isDay: nil, humidity: nil, dewPoint: nil, visibility: nil, cloudCover: nil)
    }
}
