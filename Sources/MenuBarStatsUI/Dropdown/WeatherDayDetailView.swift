import AppKit
import MenuBarStatsCore
import SwiftUI

/// A scrollable day forecast presented beside its daily row; no additional weather requests are needed.
struct WeatherDayDetailView: View {
    let day: DailyPoint
    let sample: WeatherSample
    let accent: ModuleAccent
    var settingsStore: SettingsStore? = nil
    @Environment(\.closeMenuDetail) private var dismiss

    private var forecast: Forecast { sample.forecast }
    private var detailSettings: WeatherDetailSettings {
        settingsStore?.settings.weather.detailSections ?? WeatherDetailSettings()
    }
    private var units: WeatherUnits { forecast.units }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(Self.dateTitle(day.date, timeZone: forecast.timeZone))
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close daily forecast")
            }
            .padding(14)
            Divider()
            ScrollView { forecastContent }
        }
        .frame(width: 380, height: min(640, max(300, (NSScreen.main?.visibleFrame.height ?? 900) - 100)))
    }

    var forecastContent: some View {
        let details = WeatherDayDetails(day: day, hourly: forecast.hourly, timeZone: forecast.timeZone)
        return VStack(alignment: .leading, spacing: BarometerDesign.sectionSpacing) {
            summary
            dailyMetrics
            extraSection(.precipitation)
            extraSection(.airComfort)
            hourlyForecast(details.hourly)
            sunAndMoon(details)
            extraSection(.atmosphere)
            Text("Times in \(forecast.timeZone.identifier). — means unavailable.")
                .font(.caption2).foregroundStyle(.secondary)
            if let url = URL(string: "https://open-meteo.com/") {
                Link("Weather data by Open-Meteo.com", destination: url)
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    private func extraSection(_ section: WeatherDetailSection) -> some View {
        WeatherDayExtraSections(day: day, section: section, units: units, accent: accent, preferences: detailSettings)
    }

    nonisolated static func dateTitle(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEE MMM d")
        return formatter.string(from: date)
    }

    // MARK: - Day overview

    private var summary: some View {
        GlassCard(tint: accent.primary) {
            HStack(spacing: 14) {
                Image(systemName: day.code?.symbolName(isDay: true) ?? "questionmark.circle")
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 42))
                    .frame(width: 55)
                VStack(alignment: .leading, spacing: 5) {
                    Text(forecast.location.name).font(.caption).foregroundStyle(.secondary)
                    Text(day.code?.description ?? "Conditions unavailable").font(.headline)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(temperature(day.high)).font(.system(size: 30, weight: .semibold, design: .rounded))
                        Text("Low \(temperature(day.low))").font(.callout).foregroundStyle(.secondary)
                    }
                    if sample.isStale || sample.refreshError != nil {
                        Label("Saved forecast · may be out of date", systemImage: "clock.badge.exclamationmark")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private var dailyMetrics: some View {
        WeatherDisclosureCard(section: .dayMetrics, preferences: detailSettings) {
            VStack(alignment: .leading, spacing: 8) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    tile("thermometer.medium", "Feels like high / low",
                         "\(temperature(day.apparentHigh)) / \(temperature(day.apparentLow))")
                    tile("drop.fill", "Precipitation chance", percent(day.precipitationProbability))
                    tile("cloud.rain.fill", "Precipitation total", precipitation(day.precipitation))
                    tile("sun.max.fill", "Maximum UV index", number(day.uvIndexMax))
                    tile("wind", "Maximum wind", WeatherValue.wind(day.windSpeedMax, direction: nil, units: units))
                    tile("wind.snow", "Maximum gusts",
                         WeatherValue.wind(day.windGustsMax, direction: nil, units: units))
                }
            }
        }
    }

    private func sunAndMoon(_ details: WeatherDayDetails) -> some View {
        WeatherDisclosureCard(section: .sunMoon, preferences: detailSettings, tint: .indigo) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(WeatherValue.time(day.sunrise, timeZone: forecast.timeZone), systemImage: "sunrise.fill")
                    Spacer()
                    Label(WeatherValue.time(day.sunset, timeZone: forecast.timeZone), systemImage: "sunset.fill")
                }
                .symbolRenderingMode(.multicolor)
                .font(.callout.monospacedDigit())
                if let duration = details.daylightDuration {
                    Text("\(Int(duration) / 3_600) hr \(Int(duration) % 3_600 / 60) min of daylight")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Daylight duration unavailable").font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                DisclosureGroup("Moon") {
                    HStack(spacing: 14) {
                        Image(systemName: details.moonPhase.symbolName)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.primary, .secondary.opacity(0.3))
                            .font(.system(size: 42))
                            .frame(width: 55, height: 55)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(details.moonPhase.name).font(.headline)
                            Text("About \(Int((details.moonIllumination * 100).rounded()))% illuminated")
                                .font(.callout).foregroundStyle(.secondary)
                            Text(details.usesEstimatedMoonPhase
                                 ? "Estimated at local noon" : "Daily lunar phase · Open-Meteo")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Label(moonEvent(day.details?.moonrise), systemImage: "moonrise.fill")
                            .accessibilityLabel("Moonrise: \(moonEvent(day.details?.moonrise))")
                            .help("Moonrise in \(forecast.location.name)")
                        Spacer()
                        Label(moonEvent(day.details?.moonset), systemImage: "moonset.fill")
                            .accessibilityLabel("Moonset: \(moonEvent(day.details?.moonset))")
                            .help("Moonset in \(forecast.location.name)")
                    }
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }

    private func moonEvent(_ date: Date?) -> String {
        if let date { return WeatherValue.time(date, timeZone: forecast.timeZone) }
        return day.details?.moonEventsAvailable == true ? "No event this day" : "Unavailable"
    }

    // MARK: - Hourly forecast

    private func hourlyForecast(_ points: [HourlyPoint]) -> some View {
        WeatherDisclosureCard(section: .hourly, preferences: detailSettings, tint: accent.primary) {
            VStack(alignment: .leading, spacing: 10) {
                if points.isEmpty {
                    Text("Hourly details are unavailable for this day.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: true) {
                        HourlyForecastChart(points: points, units: units, timeZone: forecast.timeZone, accent: accent)
                            .frame(width: max(336, CGFloat(points.count) * 28), height: 150)
                    }
                    .insetPlate()
                    Text("Expand an hour for more details. Blue bars show precipitation chance.")
                        .font(.caption2).foregroundStyle(.secondary)
                    ForEach(points) { point in
                        DisclosureGroup {
                            hourlyMetrics(point)
                                .padding(.vertical, 8)
                        } label: {
                            HStack(spacing: 8) {
                                Text(hourLabel(point.time)).frame(width: 76, alignment: .leading)
                                Image(systemName: point.code?.symbolName(isDay: point.isDay ?? true)
                                      ?? "questionmark.circle")
                                    .symbolRenderingMode(.multicolor).frame(width: 20)
                                Text(temperature(point.temperature)).fontWeight(.semibold)
                                Spacer(minLength: 0)
                                Label(percent(point.precipitationProbability), systemImage: "drop.fill")
                                    .foregroundStyle(.blue)
                            }
                            .font(.caption.monospacedDigit())
                            .padding(.vertical, 3)
                        }
                        .tint(accent.primary)
                        Divider()
                    }
                }
            }
        }
    }

    func hourlyMetrics(_ point: HourlyPoint) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(point.code?.description ?? "Conditions unavailable").font(.callout.weight(.medium))
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 5) {
                detail("Feels like", temperature(point.apparentTemperature))
                detail("Precipitation", precipitation(point.precipitation))
                detail("Wind", WeatherValue.wind(point.windSpeed, direction: point.windDirection, units: units))
                detail("Humidity", percent(point.humidity))
                detail("Dew point", temperature(point.dewPoint))
                detail("Cloud cover", percent(point.cloudCover))
                detail("UV index", number(point.uvIndex))
                detail("Visibility", Self.visibility(point.visibility, units: units))
            }
            .font(.caption)
            WeatherHourExtraSections(point: point, units: units, preferences: detailSettings)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Formatting

    private func hourLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = forecast.timeZone
        formatter.dateFormat = "h a z"
        return formatter.string(from: date)
    }

    private func detail(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
    }

    private func tile(_ symbol: String, _ label: String, _ value: String) -> some View {
        StatTile(symbol: symbol, label: label, value: value, tint: accent.primary)
    }

    private func temperature(_ value: Double?) -> String {
        value.map { WeatherValue.temperature($0, units: units) } ?? "—"
    }

    private func percent(_ value: Double?) -> String { value.map { String(format: "%.0f%%", $0) } ?? "—" }
    private func number(_ value: Double?) -> String { value.map { String(format: "%.1f", $0) } ?? "—" }
    private func precipitation(_ value: Double?) -> String {
        value.map { String(format: "%.2f %@", $0, units.precipitation.symbol) } ?? "—"
    }

    /// The decoder normalizes provider visibility to meters before customary or metric display conversion.
    nonisolated static func visibility(_ meters: Double?, units: WeatherUnits) -> String {
        guard let meters else { return "—" }
        return units.temperature == .fahrenheit
            ? String(format: "%.1f mi", meters / 1_609.344)
            : String(format: "%.1f km", meters / 1_000)
    }
}
