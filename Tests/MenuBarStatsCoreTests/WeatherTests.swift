import Foundation
import Testing
@testable import MenuBarStatsCore

@Suite("WeatherTests")
struct WeatherTests {
    private let boston = Location(
        id: "boston-ma-us",
        name: "Boston",
        admin: "Massachusetts",
        country: "United States",
        latitude: 42.3601,
        longitude: -71.0589,
        timeZone: "America/New_York"
    )

    @Test("forecast fixture decodes all requested detail")
    func decodeForecast() throws {
        let data = try fixture(named: "forecast-boston")
        let forecast = try OpenMeteoClient.decodeForecast(data, for: boston, units: .imperial)

        #expect(forecast.location == boston)
        #expect(forecast.current.temperature == 66.4)
        #expect(forecast.current.apparentTemperature == 70.2)
        #expect(forecast.current.code.rawValue == 3)
        #expect(forecast.current.isDay == false)
        #expect(forecast.hourly.count == 240)
        #expect(forecast.daily.count == 10)
        #expect(forecast.daily.first?.high == 72.9)
        #expect(forecast.timeZone.identifier == "America/New_York")
    }

    @Test("geocoding fixture maps stable location fields")
    func decodeGeocoding() throws {
        let results = try OpenMeteoClient.decodeGeocoding(try fixture(named: "geocoding-boston"))
        let first = try #require(results.first)

        #expect(results.count == 10)
        #expect(first.name == "Boston")
        #expect(first.admin == "Massachusetts")
        #expect(first.country == "United States")
        #expect(first.timeZone == "America/New_York")
        #expect(first.population == 653_833)
    }

    @Test("geocoding response without results maps to an empty list")
    func decodeEmptyGeocoding() throws {
        let results = try OpenMeteoClient.decodeGeocoding(Data(#"{"generationtime_ms":0.1}"#.utf8))
        #expect(results.isEmpty)
    }

    @Test("air quality fixture maps current pollutant values")
    func decodeAirQuality() throws {
        let quality = try OpenMeteoClient.decodeAirQuality(
            try fixture(named: "air-quality-boston"),
            for: boston
        )

        #expect(quality.usAQI == 52)
        #expect(quality.pm2_5 == 14.6)
        #expect(quality.pm10 == 14.7)
        #expect(quality.ozone == 54)
    }

    @Test("current condition consensus uses median values and an agreed condition")
    func currentConditionConsensus() throws {
        let time = Date(timeIntervalSince1970: 1_788_500_000)
        let cloudy = current(time: time, temperature: 70.8, code: 3, precipitation: 0)
        let ecmwf = current(time: time, temperature: 69.6, code: 51, precipitation: 0.004)
        let gem = current(time: time, temperature: 71.8, code: 51, precipitation: 0.004)

        let result = try #require(OpenMeteoClient.consensusCurrent([cloudy, ecmwf, gem], fallback: cloudy))

        #expect(result.temperature == 70.8)
        #expect(result.precipitation == 0.004)
        #expect(result.code.rawValue == 51)
    }

    @Test("current condition consensus does not invent a condition without agreement")
    func currentConditionConsensusTie() throws {
        let time = Date(timeIntervalSince1970: 1_788_500_000)
        let first = current(time: time, temperature: 70, code: 3, precipitation: 0)
        let second = current(time: time, temperature: 72, code: 51, precipitation: 0.004)

        let result = try #require(OpenMeteoClient.consensusCurrent([first, second], fallback: first))

        #expect(result.temperature == 71)
        #expect(result.code.rawValue == 3)
    }

    @Test("WMO codes provide descriptions and day/night symbols", arguments: [
        (0, "Clear sky", "sun.max", "moon.stars"),
        (3, "Overcast", "cloud", "cloud"),
        (45, "Fog", "cloud.fog", "cloud.fog"),
        (65, "Heavy rain", "cloud.heavyrain", "cloud.heavyrain"),
        (71, "Light snow", "cloud.snow", "cloud.snow"),
        (95, "Thunderstorm", "cloud.bolt", "cloud.bolt"),
        (99, "Thunderstorm with heavy hail", "cloud.bolt.rain", "cloud.bolt.rain"),
    ])
    func mapWMO(code: Int, description: String, day: String, night: String) {
        let value = WMOCode(rawValue: code)
        #expect(value.description == description)
        #expect(value.symbolName(isDay: true) == day)
        #expect(value.symbolName(isDay: false) == night)
    }

    @Test("known lunar epochs map to new and full moon")
    func moonPhase() throws {
        let formatter = ISO8601DateFormatter()
        let newMoonDate = try #require(formatter.date(from: "2000-01-06T18:14:00Z"))
        let fullMoonDate = try #require(formatter.date(from: "2000-01-21T12:00:00Z"))

        #expect(MoonPhase.calculate(for: newMoonDate) == .newMoon)
        #expect(MoonPhase.calculate(for: fullMoonDate) == .fullMoon)
    }

    @Test("moon phases map to valid SF Symbol names", arguments: [
        (MoonPhase.newMoon, "moonphase.new.moon"),
        (.waxingCrescent, "moonphase.waxing.crescent"),
        (.firstQuarter, "moonphase.first.quarter"),
        (.waxingGibbous, "moonphase.waxing.gibbous"),
        (.fullMoon, "moonphase.full.moon"),
        (.waningGibbous, "moonphase.waning.gibbous"),
        (.lastQuarter, "moonphase.last.quarter"),
        (.waningCrescent, "moonphase.waning.crescent"),
    ])
    func moonPhaseSymbol(phase: MoonPhase, symbol: String) {
        #expect(phase.symbolName == symbol)
    }

    @Test("menu bar formatting supports Fahrenheit, Celsius, and stale state")
    func menuBarFormatting() throws {
        let data = try fixture(named: "forecast-boston")
        let imperial = try OpenMeteoClient.decodeForecast(data, for: boston, units: .imperial)
        let metric = try OpenMeteoClient.decodeForecast(data, for: boston, units: .metric)
        let imperialSample = WeatherSample(
            timestamp: imperial.fetchedAt,
            forecast: imperial,
            airQuality: nil,
            isStale: false,
            refreshError: nil
        )
        let metricSample = WeatherSample(
            timestamp: metric.fetchedAt,
            forecast: metric,
            airQuality: nil,
            isStale: true,
            refreshError: "offline"
        )

        #expect(
            WeatherPresentationFormatter.menuBar(
                sample: imperialSample,
                mode: "iconTemperature"
            ).text == "66°F"
        )
        #expect(
            WeatherPresentationFormatter.menuBar(
                sample: metricSample,
                mode: "temperature"
            ).text == "66°C"
        )
    }

    private func fixture(named name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func current(
        time: Date,
        temperature: Double,
        code: Int,
        precipitation: Double
    ) -> CurrentConditions {
        CurrentConditions(
            time: time,
            temperature: temperature,
            apparentTemperature: temperature,
            humidity: 90,
            precipitation: precipitation,
            rain: precipitation,
            showers: 0,
            snowfall: 0,
            code: WMOCode(rawValue: code),
            isDay: false,
            cloudCover: 100,
            pressureMSL: 1_010,
            surfacePressure: 1_000,
            windSpeed: 5,
            windDirection: 180,
            windGusts: 8
        )
    }
}
