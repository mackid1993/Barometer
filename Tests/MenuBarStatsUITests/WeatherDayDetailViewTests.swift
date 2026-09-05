import AppKit
import SwiftUI
import Testing

@testable import MenuBarStatsCore
@testable import MenuBarStatsUI

@Suite("WeatherDayDetailViewTests")
@MainActor
struct WeatherDayDetailViewTests {
    @Test("Visibility uses readable metric and customary distance units")
    func visibility() {
        #expect(WeatherDayDetailView.visibility(16_093.44, units: .imperial) == "10.0 mi")
        #expect(WeatherDayDetailView.visibility(12_000, units: .metric) == "12.0 km")
        #expect(WeatherDayDetailView.visibility(nil, units: .metric) == "—")
    }

    @Test("Provider detail units remain explicit with independently selected weather units")
    func detailUnits() {
        #expect(WeatherDetailUnit.snowfall.format(1, units: .imperial) == "1.0 in")
        #expect(WeatherDetailUnit.snowfall.format(1, units: .metric) == "1.0 cm")
        #expect(WeatherDetailUnit.duration.format(43_260, units: .metric) == "12 hr 1 min")
        #expect(WeatherDetailUnit.pressure.format(1_013.25, units: .imperial) == "29.92 inHg")
        #expect(WeatherDetailUnit.radiation.format(nil, units: .metric) == "—")
        #expect(WeatherDetailUnit.number.format(.infinity, units: .metric) == "—")
        #expect(WeatherDetailUnit.height.format(3_048, units: .imperial) == "10000 ft")
        #expect(WeatherDetailUnit.snowDepth.format(0.254, units: .imperial) == "10.0 in")
        #expect(WeatherDetailUnit.snowDepth.format(0.254, units: .metric) == "25.4 cm")
    }

    @Test("Day title follows the forecast location near midnight")
    func dateTitle() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-09-05T01:00:00Z"))
        let zone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let title = WeatherDayDetailView.dateTitle(date, timeZone: zone)
        let expected = DateFormatter()
        expected.timeZone = zone
        expected.setLocalizedDateFormatFromTemplate("EEEE MMM d")
        #expect(title == expected.string(from: date))
        #expect(title != WeatherDayDetailView.dateTitle(date, timeZone: .gmt))
    }

    @Test("Day detail has bounded hosted dimensions in both appearances")
    func hostedLayout() throws {
        let location = Location(
            id: "boston", name: "Boston", admin: nil, country: "US",
            latitude: 42.36, longitude: -71.05, timeZone: "America/New_York")
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MenuBarStatsCoreTests/Fixtures/forecast-rich-imperial.json")
        let forecast = try OpenMeteoClient.decodeForecast(Data(contentsOf: fixture), for: location, units: .imperial)
        let sample = WeatherSample(
            timestamp: forecast.fetchedAt, forecast: forecast, airQuality: nil,
            isStale: false, refreshError: nil)
        let day = try #require(forecast.daily.first)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let view = NSHostingView(
                rootView: WeatherDayDetailView(
                    day: day, sample: sample, accent: .signature(for: .weather)))
            view.appearance = NSAppearance(named: appearance)
            view.frame = NSRect(x: 0, y: 0, width: 380, height: 640)
            view.layoutSubtreeIfNeeded()
            #expect(view.fittingSize.width == 380)
            #expect(view.fittingSize.height <= 640)
            if let directory = ProcessInfo.processInfo.environment["WEATHER_SNAPSHOT_DIRECTORY"] {
                let content = WeatherDayDetailView(day: day, sample: sample, accent: .signature(for: .weather))
                let renderer = ImageRenderer(
                    content: content.forecastContent
                        .frame(width: 380)
                        .background(name == "dark" ? Color(white: 0.12) : Color(white: 0.96))
                        .environment(\.colorScheme, name == "dark" ? .dark : .light))
                renderer.scale = 2
                let image = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
                let data = try #require(image.representation(using: .png, properties: [:]))
                try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("weather-day-\(name).png"))
                let hours = WeatherDayDetails(day: day, hourly: forecast.hourly, timeZone: forecast.timeZone).hourly
                let chartRenderer = ImageRenderer(
                    content: HourlyForecastChart(
                        points: hours, units: forecast.units, timeZone: forecast.timeZone,
                        accent: .signature(for: .weather)
                    )
                    .frame(width: 672, height: 150)
                    .background(name == "dark" ? Color(white: 0.12) : Color(white: 0.96))
                    .environment(\.colorScheme, name == "dark" ? .dark : .light))
                chartRenderer.scale = 2
                let chartImage = NSBitmapImageRep(cgImage: try #require(chartRenderer.cgImage))
                let chartData = try #require(chartImage.representation(using: .png, properties: [:]))
                try chartData.write(
                    to: URL(fileURLWithPath: directory)
                        .appendingPathComponent("weather-chart-\(name).png"))
                if let point = forecast.hourly.first {
                    let hourlyRenderer = ImageRenderer(
                        content: content.hourlyMetrics(point)
                            .padding(12).frame(width: 356)
                            .background(name == "dark" ? Color(white: 0.12) : Color(white: 0.96))
                            .environment(\.colorScheme, name == "dark" ? .dark : .light))
                    hourlyRenderer.scale = 2
                    let hourly = NSBitmapImageRep(cgImage: try #require(hourlyRenderer.cgImage))
                    let hourlyData = try #require(hourly.representation(using: .png, properties: [:]))
                    try hourlyData.write(
                        to: URL(fileURLWithPath: directory)
                            .appendingPathComponent("weather-hour-\(name).png"))
                }
            }
        }
    }
}
