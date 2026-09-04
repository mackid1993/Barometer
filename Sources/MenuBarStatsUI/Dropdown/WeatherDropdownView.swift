import AppKit
import MenuBarStatsCore
import SwiftUI

/// Detailed live forecast shown inside the Weather status-item menu.
public struct WeatherDropdownView: View {
    private let store: ModuleStore<WeatherSample>
    private let settingsStore: SettingsStore
    private let refreshAction: @MainActor () -> Void

    /// Creates a Weather dropdown backed by the supplied observable store.
    public init(
        store: ModuleStore<WeatherSample>,
        settingsStore: SettingsStore,
        refreshAction: @escaping @MainActor () -> Void
    ) {
        self.store = store
        self.settingsStore = settingsStore
        self.refreshAction = refreshAction
    }

    public var body: some View {
        let _ = store.revision
        ScrollView {
            if let sample = store.latestSample {
                VStack(alignment: .leading, spacing: 16) {
                    CurrentWeatherHeader(sample: sample)
                    HourlyForecastSection(sample: sample)
                    DailyForecastSection(sample: sample)
                    SunMoonSection(sample: sample)
                    AirQualitySection(sample: sample)
                    WeatherDetailsSection(sample: sample)
                    locationAndActions(sample: sample)
                    attribution
                }
                .padding(16)
            } else {
                ContentUnavailableView(
                    "Weather unavailable",
                    systemImage: "cloud.sun",
                    description: Text(emptyStateDescription)
                )
                .frame(maxWidth: .infinity, minHeight: 620)
                .padding(20)
            }
        }
        .frame(width: 420, height: 700)
    }

    private var emptyStateDescription: String {
        settingsStore.settings.weather.primaryLocation == nil
            ? "Add a location in Weather settings."
            : "Waiting for the first forecast."
    }

    @ViewBuilder
    private func locationAndActions(sample: WeatherSample) -> some View {
        Divider()
        HStack {
            if settingsStore.settings.weather.locations.count > 1 {
                Picker("Location", selection: primaryLocationBinding) {
                    ForEach(settingsStore.settings.weather.locations) { location in
                        Text(location.name).tag(location.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 180)
            } else {
                Label(sample.forecast.location.name, systemImage: "location")
                    .lineLimit(1)
            }
            Spacer()
            Button(action: refreshAction) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            Button(action: openWeatherApplication) {
                Label("Weather", systemImage: "arrow.up.forward.app")
            }
        }
        .controlSize(.small)
    }

    private var primaryLocationBinding: Binding<String> {
        Binding(
            get: {
                settingsStore.settings.weather.primaryLocation?.id
                    ?? settingsStore.settings.weather.locations.first?.id
                    ?? ""
            },
            set: { identifier in
                var appSettings = settingsStore.settings
                appSettings.weather.primaryLocationID = identifier
                settingsStore.settings = appSettings
            }
        )
    }

    @ViewBuilder
    private var attribution: some View {
        HStack {
            Spacer()
            if let url = URL(string: "https://open-meteo.com/") {
                Link("Weather data by Open-Meteo.com", destination: url)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Weather data by Open-Meteo.com")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func openWeatherApplication() {
        guard let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.weather")
        else {
            return
        }
        NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}

private struct CurrentWeatherHeader: View {
    let sample: WeatherSample

    var body: some View {
        let forecast = sample.forecast
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: forecast.current.code.symbolName(isDay: forecast.current.isDay))
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 42, weight: .medium))
                .frame(width: 54)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(forecast.location.name).font(.headline)
                    if sample.isStale {
                        Label("Stale", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                Text(forecast.current.code.description)
                    .foregroundStyle(.secondary)
                if let apparent = forecast.current.apparentTemperature {
                    Text("Feels like \(WeatherValue.temperature(apparent, units: forecast.units))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(WeatherValue.temperature(forecast.current.temperature, units: forecast.units))
                .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
        }
    }
}

private struct HourlyForecastSection: View {
    let sample: WeatherSample

    private var points: [HourlyPoint] {
        Array(sample.forecast.hourly.filter { $0.time >= sample.forecast.current.time }.prefix(48))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NEXT 48 HOURS").weatherSectionLabel()
            ScrollView(.horizontal, showsIndicators: false) {
                HourlyForecastChart(
                    points: points,
                    units: sample.forecast.units,
                    timeZone: sample.forecast.timeZone
                )
                    .frame(width: max(760, CGFloat(points.count) * 28), height: 150)
            }
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
        }
    }
}

private struct HourlyForecastChart: View {
    let points: [HourlyPoint]
    let units: WeatherUnits
    let timeZone: TimeZone

    var body: some View {
        let temperatures = points.compactMap(\.temperature)
        let minimum = temperatures.min() ?? 0
        let maximum = temperatures.max() ?? minimum + 1
        let spread = max(1, maximum - minimum)

        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                guard points.count > 1 else {
                    return
                }
                let step = size.width / CGFloat(points.count)
                for (index, point) in points.enumerated() {
                    let probability = CGFloat((point.precipitationProbability ?? 0) / 100)
                    let height = probability * 26
                    let rect = CGRect(
                        x: CGFloat(index) * step + step * 0.22,
                        y: size.height - height - 5,
                        width: max(2, step * 0.56),
                        height: height
                    )
                    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(.blue.opacity(0.65)))
                }

                var path = Path()
                for (index, point) in points.enumerated() {
                    guard let temperature = point.temperature else {
                        continue
                    }
                    let x = (CGFloat(index) + 0.5) * step
                    let normalized = CGFloat((temperature - minimum) / spread)
                    let y = 91 - normalized * 42
                    index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
                }
                context.stroke(path, with: .color(.cyan), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            }

            HStack(spacing: 0) {
                ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                    if index.isMultiple(of: 3) {
                        VStack(spacing: 4) {
                            Text(WeatherValue.hour(point.time, timeZone: timeZone))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Image(systemName: point.code?.symbolName(isDay: point.isDay ?? true) ?? "cloud")
                                .symbolRenderingMode(.multicolor)
                            Text(point.temperature.map { String(format: "%.0f°", $0) } ?? "—")
                                .font(.caption.weight(.semibold).monospacedDigit())
                            Spacer()
                            if let probability = point.precipitationProbability, probability > 0 {
                                Text(String(format: "%.0f%%", probability))
                                    .font(.system(size: 8).monospacedDigit())
                                    .foregroundStyle(.blue)
                            }
                        }
                        .frame(width: 84)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

}

private struct DailyForecastSection: View {
    let sample: WeatherSample

    var body: some View {
        let daily = sample.forecast.daily
        let minimum = daily.compactMap(\.low).min() ?? 0
        let maximum = daily.compactMap(\.high).max() ?? minimum + 1
        VStack(alignment: .leading, spacing: 7) {
            Text("10-DAY FORECAST").weatherSectionLabel()
            ForEach(daily) { day in
                DailyForecastRow(
                    day: day,
                    units: sample.forecast.units,
                    timeZone: sample.forecast.timeZone,
                    overallMinimum: minimum,
                    overallMaximum: maximum
                )
            }
        }
    }
}

private struct DailyForecastRow: View {
    let day: DailyPoint
    let units: WeatherUnits
    let timeZone: TimeZone
    let overallMinimum: Double
    let overallMaximum: Double

    var body: some View {
        HStack(spacing: 9) {
            Text(WeatherValue.weekday(day.date, timeZone: timeZone))
                .frame(width: 34, alignment: .leading)
            Image(systemName: day.code?.symbolName(isDay: true) ?? "cloud")
                .symbolRenderingMode(.multicolor)
                .frame(width: 20)
            if let probability = day.precipitationProbability, probability > 0 {
                Text(String(format: "%.0f%%", probability))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.blue)
                    .frame(width: 29, alignment: .trailing)
            } else {
                Text("").frame(width: 29)
            }
            Text(day.low.map { String(format: "%.0f°", $0) } ?? "—")
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 30, alignment: .trailing)
            TemperatureRangeBar(
                low: day.low,
                high: day.high,
                overallMinimum: overallMinimum,
                overallMaximum: overallMaximum
            )
            Text(day.high.map { String(format: "%.0f°", $0) } ?? "—")
                .monospacedDigit()
                .frame(width: 30, alignment: .trailing)
        }
        .font(.caption)
    }
}

private struct TemperatureRangeBar: View {
    let low: Double?
    let high: Double?
    let overallMinimum: Double
    let overallMaximum: Double

    var body: some View {
        GeometryReader { geometry in
            let spread = max(1, overallMaximum - overallMinimum)
            let start = CGFloat(((low ?? overallMinimum) - overallMinimum) / spread)
            let end = CGFloat(((high ?? overallMaximum) - overallMinimum) / spread)
            Capsule().fill(.quaternary)
            Capsule()
                .fill(LinearGradient(colors: [.cyan, .yellow, .orange], startPoint: .leading, endPoint: .trailing))
                .frame(width: max(5, (end - start) * geometry.size.width))
                .offset(x: start * geometry.size.width)
        }
        .frame(height: 5)
    }
}

private struct SunMoonSection: View {
    let sample: WeatherSample

    var body: some View {
        let today = sample.forecast.daily.first
        let phase = MoonPhase.calculate(for: sample.forecast.current.time)
        VStack(alignment: .leading, spacing: 8) {
            Text("SUN & MOON").weatherSectionLabel()
            HStack {
                WeatherFact(
                    symbol: "sunrise.fill",
                    label: "Sunrise",
                    value: WeatherValue.time(today?.sunrise, timeZone: sample.forecast.timeZone)
                )
                WeatherFact(
                    symbol: "sunset.fill",
                    label: "Sunset",
                    value: WeatherValue.time(today?.sunset, timeZone: sample.forecast.timeZone)
                )
                WeatherFact(symbol: phase.symbolName, label: "Moon", value: phase.name)
            }
        }
    }
}

private struct AirQualitySection: View {
    let sample: WeatherSample

    var body: some View {
        if let airQuality = sample.airQuality {
            VStack(alignment: .leading, spacing: 8) {
                Text("AIR QUALITY").weatherSectionLabel()
                HStack(spacing: 12) {
                    if let value = airQuality.usAQI {
                        Text("\(value)")
                            .font(.title2.bold().monospacedDigit())
                            .foregroundStyle(WeatherValue.aqiColor(value))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("US AQI").font(.caption).foregroundStyle(.secondary)
                            Text(WeatherValue.aqiDescription(value)).font(.caption.weight(.semibold))
                        }
                    }
                    Spacer()
                    if let value = airQuality.pm2_5 {
                        WeatherFact(symbol: "aqi.medium", label: "PM2.5", value: String(format: "%.1f", value))
                    }
                    if let value = airQuality.pm10 {
                        WeatherFact(symbol: "aqi.low", label: "PM10", value: String(format: "%.1f", value))
                    }
                }
                .padding(10)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
            }
        }
    }
}

private struct WeatherDetailsSection: View {
    let sample: WeatherSample

    var body: some View {
        let current = sample.forecast.current
        let units = sample.forecast.units
        VStack(alignment: .leading, spacing: 8) {
            Text("DETAILS").weatherSectionLabel()
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 9) {
                GridRow {
                    WeatherFact(
                        symbol: "humidity",
                        label: "Humidity",
                        value: current.humidity.map { String(format: "%.0f%%", $0) } ?? "—"
                    )
                    WeatherFact(
                        symbol: "wind",
                        label: "Wind",
                        value: WeatherValue.wind(current.windSpeed, direction: current.windDirection, units: units)
                    )
                }
                GridRow {
                    WeatherFact(
                        symbol: "gauge.with.dots.needle.50percent",
                        label: "Pressure",
                        value: WeatherValue.pressure(current.pressureMSL, units: units)
                    )
                    WeatherFact(
                        symbol: "cloud.fill",
                        label: "Cloud cover",
                        value: current.cloudCover.map { String(format: "%.0f%%", $0) } ?? "—"
                    )
                }
                GridRow {
                    WeatherFact(
                        symbol: "drop.fill",
                        label: "Precipitation",
                        value: current.precipitation.map {
                            String(format: "%.2f %@", $0, units.precipitation.symbol)
                        } ?? "—"
                    )
                    WeatherFact(
                        symbol: "wind.snow",
                        label: "Gusts",
                        value: current.windGusts.map {
                            String(format: "%.0f %@", $0, units.windSpeed.symbol)
                        } ?? "—"
                    )
                }
            }
        }
    }
}

private struct WeatherFact: View {
    let symbol: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.cyan)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.caption.weight(.medium)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum WeatherValue {
    static func temperature(_ value: Double, units: WeatherUnits) -> String {
        String(format: "%.0f%@", value, units.temperature.symbol)
    }

    static func hour(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        formatter.amSymbol = "am"
        formatter.pmSymbol = "pm"
        formatter.timeZone = timeZone
        return formatter.string(from: date).lowercased()
    }

    static func weekday(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }

    static func time(_ date: Date?, timeZone: TimeZone) -> String {
        guard let date else {
            return "—"
        }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }

    static func pressure(_ value: Double?, units: WeatherUnits) -> String {
        guard let value else {
            return "—"
        }
        switch units.pressure {
        case .hectopascals:
            return String(format: "%.0f hPa", value)
        case .inchesOfMercury:
            return String(format: "%.2f inHg", value / 33.863_886_666_7)
        case .millimetersOfMercury:
            return String(format: "%.0f mmHg", value * 0.750_061_683)
        }
    }

    static func wind(_ speed: Double?, direction: Double?, units: WeatherUnits) -> String {
        guard let speed else {
            return "—"
        }
        let compass = direction.map(compassDirection) ?? ""
        return String(format: "%@ %.0f %@", compass, speed, units.windSpeed.symbol)
            .trimmingCharacters(in: .whitespaces)
    }

    static func compassDirection(_ degrees: Double) -> String {
        let values = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let normalized = degrees.truncatingRemainder(dividingBy: 360) + (degrees < 0 ? 360 : 0)
        return values[Int((normalized / 45).rounded()) % values.count]
    }

    static func aqiDescription(_ value: Int) -> String {
        switch value {
        case ...50: "Good"
        case ...100: "Moderate"
        case ...150: "Unhealthy for sensitive groups"
        case ...200: "Unhealthy"
        case ...300: "Very unhealthy"
        default: "Hazardous"
        }
    }

    static func aqiColor(_ value: Int) -> Color {
        switch value {
        case ...50: .green
        case ...100: .yellow
        case ...150: .orange
        case ...200: .red
        case ...300: .purple
        default: .brown
        }
    }
}

private extension View {
    func weatherSectionLabel() -> some View {
        font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
    }
}
