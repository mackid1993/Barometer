import Foundation
import Testing

@testable import MenuBarStatsCore

@Suite("WeatherDetailDecodingTests")
struct WeatherDetailDecodingTests {
    private let location = Location(
        id: "boston", name: "Boston", admin: "MA", country: "US", latitude: 42.36, longitude: -71.06,
        timeZone: "America/New_York"
    )

    @Test("live metric and imperial fixtures preserve every additional API field", arguments: [false, true])
    func richFixtures(imperial: Bool) throws {
        let data = try fixture(imperial ? "forecast-rich-imperial" : "forecast-rich-metric")
        let raw = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hours = try #require(raw["hourly"] as? [String: Any])
        let days = try #require(raw["daily"] as? [String: Any])
        let hourlyUnits = try #require(raw["hourly_units"] as? [String: String])
        let dailyUnits = try #require(raw["daily_units"] as? [String: String])
        let forecast = try OpenMeteoClient.decodeForecast(data, for: location, units: imperial ? .imperial : .metric)
        #expect(forecast.hourly.count == 48)
        #expect(forecast.daily.count == 2)
        for metric in HourlyWeatherMetric.allCases {
            let values = try #require(hours[metric.rawValue] as? [Any])
            for index in values.indices {
                var expected = (values[index] as? NSNumber)?.doubleValue
                if [.snowDepth, .freezingLevelHeight].contains(metric), hourlyUnits[metric.rawValue] == "ft" {
                    expected = expected.map { $0 * 0.3048 }
                }
                #expect(forecast.hourly[index].details?[metric] == expected)
            }
        }
        for metric in DailyWeatherMetric.allCases {
            let values = try #require(days[metric.rawValue] as? [Any])
            for index in values.indices {
                var expected = (values[index] as? NSNumber)?.doubleValue
                if [.visibilityMean, .visibilityMin].contains(metric), dailyUnits[metric.rawValue] == "ft" {
                    expected = expected.map { $0 * 0.3048 }
                }
                #expect(forecast.daily[index].details?[metric] == expected)
            }
        }
        let rawVisibility = try #require((hours["visibility"] as? [Double])?.first)
        #expect(forecast.hourly.first?.visibility == rawVisibility * (hourlyUnits["visibility"] == "ft" ? 0.3048 : 1))
        #expect(forecast.daily.first?.details?.moonEventsAvailable == true)
        let rise = try #require(forecast.daily.first?.details?.moonrise)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = forecast.timeZone
        #expect(calendar.component(.hour, from: rise) == 23)
        #expect(forecast.daily[1].details?.moonrise == nil)
        #expect(forecast.daily[1].details?.moonEventsAvailable == true)
        let cached = try JSONDecoder().decode(Forecast.self, from: JSONEncoder().encode(forecast))
        #expect(cached == forecast)
    }

    @Test("older caches without details still decode")
    func oldCache() throws {
        let forecast = try OpenMeteoClient.decodeForecast(
            try fixture("forecast-boston"), for: location, units: .imperial)
        var raw = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(forecast)) as? [String: Any])
        for key in ["hourly", "daily"] {
            var points = try #require(raw[key] as? [[String: Any]])
            for index in points.indices { points[index].removeValue(forKey: "details") }
            raw[key] = points
        }
        let decoded = try JSONDecoder().decode(Forecast.self, from: JSONSerialization.data(withJSONObject: raw))
        #expect(decoded.hourly.count == 240)
        #expect(decoded.hourly.allSatisfy { $0.details == nil })
        #expect(decoded.daily.allSatisfy { $0.details == nil })
    }

    @Test("missing null and short optional arrays never invent weather or lunar events")
    func sparseOptionalValues() throws {
        var raw = try #require(JSONSerialization.jsonObject(with: fixture("forecast-rich-metric")) as? [String: Any])
        var hours = try #require(raw["hourly"] as? [String: Any])
        hours["rain"] = [NSNull(), 2.5]
        hours.removeValue(forKey: "cloud_cover_low")
        raw["hourly"] = hours
        var days = try #require(raw["daily"] as? [String: Any])
        days.removeValue(forKey: "moonrise")
        days.removeValue(forKey: "moonset")
        raw["daily"] = days
        let decoded = try OpenMeteoClient.decodeForecast(
            JSONSerialization.data(withJSONObject: raw), for: location, units: .metric
        )
        #expect(decoded.hourly[0].details?[.rain] == nil)
        #expect(decoded.hourly[1].details?[.rain] == 2.5)
        #expect(decoded.hourly[2].details?[.rain] == nil)
        #expect(decoded.hourly.allSatisfy { $0.details?[.cloudCoverLow] == nil })
        #expect(decoded.daily.first?.details?.moonEventsAvailable == false)
    }

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }
}
