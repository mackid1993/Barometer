import AppKit
import MenuBarStatsCore
import SwiftUI

/// Detailed live forecast shown inside the Weather status-item menu.
public struct WeatherDropdownView: View {
    /// Fixed hosted content width; height follows the content.
    public static let contentSize = CGSize(width: 380, height: 720)

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
        let accent = ModuleAccent.resolve(settingsStore.settings, module: .weather)
        DropdownScaffold(size: Self.contentSize) {
            if let sample = store.latestSample {
                CurrentWeatherCard(sample: sample)
                HourlyForecastSection(sample: sample, accent: accent)
                DailyForecastSection(sample: sample, accent: accent, settingsStore: settingsStore)
                SunMoonSection(sample: sample, accent: accent)
                AirQualitySection(sample: sample)
                WeatherDetailsSection(sample: sample, accent: accent)
                locationAndActions(sample: sample, accent: accent)
                attribution
            } else {
                HeroHeader(
                    symbolName: "cloud.sun.fill", title: "Weather", subtitle: emptyStateDescription, value: nil,
                    accent: accent)
                GlassCard {
                    ContentUnavailableView(
                        "Weather unavailable",
                        systemImage: "cloud.sun",
                        description: Text(emptyStateDescription)
                    )
                }
            }
        }
    }

    private var emptyStateDescription: String {
        settingsStore.settings.weather.primaryLocation == nil
            ? "Add a location in Weather settings."
            : "Waiting for the first forecast."
    }

    @ViewBuilder
    private func locationAndActions(sample: WeatherSample, accent: ModuleAccent) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if settingsStore.settings.weather.locations.count > 1 {
                        Picker("Location", selection: primaryLocationBinding) {
                            ForEach(settingsStore.settings.weather.locations) { location in
                                Text(location.name).tag(location.id)
                            }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(maxWidth: 180)
                    } else {
                        Chip(text: sample.forecast.location.name, color: accent.primary, symbol: "location.fill")
                    }
                    Spacer()
                    DropdownActionButton(title: "Refresh", symbol: "arrow.clockwise", action: refreshAction)
                    DropdownActionButton(
                        title: "Weather", symbol: "arrow.up.forward.app", action: openWeatherApplication)
                }
                if let refreshError = sample.refreshError {
                    Label(
                        "Refresh failed; showing saved weather. \(refreshError)",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                }
            }
        }
    }

    static func updatedText(
        fetchedAt: Date,
        now: Date,
        timeZone: TimeZone = .current
    ) -> String {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.dateStyle = calendar.isDate(fetchedAt, inSameDayAs: now) ? .none : .medium
        formatter.timeStyle = .short
        formatter.timeZone = timeZone
        let absoluteTime = formatter.string(from: fetchedAt)
        let fetchedMinute = floor(fetchedAt.timeIntervalSince1970 / 60)
        let currentMinute = floor(now.timeIntervalSince1970 / 60)
        let elapsedMinutes = max(0, Int(currentMinute - fetchedMinute))
        let relativeTime: String
        if elapsedMinutes == 0 {
            relativeTime = "just now"
        } else if elapsedMinutes < 60 {
            relativeTime = "\(elapsedMinutes) min ago"
        } else if elapsedMinutes < 1_440 {
            relativeTime = "\(elapsedMinutes / 60) hr ago"
        } else {
            relativeTime = "\(elapsedMinutes / 1_440) days ago"
        }
        return "Updated \(absoluteTime) · \(relativeTime)"
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

/// Sky-tinted hero card with the current conditions.
private struct CurrentWeatherCard: View {
    let sample: WeatherSample
    @State private var now = Date()

    var body: some View {
        let forecast = sample.forecast
        let current = forecast.current
        let sky = WeatherSky.gradient(code: current.code, isDay: current.isDay)
        let shape = RoundedRectangle(cornerRadius: BarometerDesign.cardRadius, style: .continuous)
        ZStack(alignment: .topLeading) {
            shape.fill(sky)
            shape.fill(
                LinearGradient(
                    colors: [.white.opacity(0.18), .clear, .black.opacity(0.12)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: current.code.symbolName(isDay: current.isDay))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 46, weight: .medium))
                        .frame(width: 60)
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            Text(forecast.location.name)
                                .font(.system(.title3, design: .rounded).weight(.semibold))
                                .lineLimit(1)
                            if sample.isStale {
                                Chip(text: "Stale", color: .orange, symbol: "exclamationmark.triangle.fill")
                            }
                        }
                        Text(current.code.description)
                            .font(.callout)
                            .opacity(0.9)
                        if let apparent = current.apparentTemperature {
                            Text("Feels like \(WeatherValue.temperature(apparent, units: forecast.units))")
                                .font(.caption)
                                .opacity(0.8)
                        }
                    }
                    Spacer(minLength: 6)
                    Text(WeatherValue.temperature(current.temperature, units: forecast.units))
                        .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                }
                Label(
                    WeatherDropdownView.updatedText(
                        fetchedAt: forecast.fetchedAt,
                        now: now
                    ),
                    systemImage: "clock.arrow.circlepath"
                )
                .font(.caption2.weight(.medium))
                .opacity(0.82)
                .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(14)
        }
        .overlay(shape.strokeBorder(.white.opacity(0.22), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .task {
            while !Task.isCancelled {
                now = Date()
                do {
                    try await Task.sleep(for: .seconds(15))
                } catch {
                    return
                }
            }
        }
    }
}

private enum WeatherSky {
    static func gradient(code: WMOCode, isDay: Bool) -> LinearGradient {
        let colors: [Color]
        if !isDay {
            colors = [Color(hex: 0x1E1B4B), Color(hex: 0x0F172A)]
        } else {
            switch code.category {
            case .clear: colors = [Color(hex: 0x38BDF8), Color(hex: 0x2563EB)]
            case .cloudy: colors = [Color(hex: 0x64748B), Color(hex: 0x334155)]
            case .rain: colors = [Color(hex: 0x3B82F6), Color(hex: 0x1E3A8A)]
            case .snow: colors = [Color(hex: 0x93C5FD), Color(hex: 0x475569)]
            case .storm: colors = [Color(hex: 0x4C1D95), Color(hex: 0x1E1B4B)]
            case .fog: colors = [Color(hex: 0x94A3B8), Color(hex: 0x475569)]
            }
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension WMOCode {
    fileprivate enum Category { case clear, cloudy, rain, snow, storm, fog }

    fileprivate var category: Category {
        let symbol = symbolName(isDay: true)
        if symbol.contains("bolt") { return .storm }
        if symbol.contains("snow") || symbol.contains("sleet") { return .snow }
        if symbol.contains("rain") || symbol.contains("drizzle") { return .rain }
        if symbol.contains("fog") { return .fog }
        if symbol.contains("sun.max") { return .clear }
        return .cloudy
    }
}

private struct HourlyForecastSection: View {
    let sample: WeatherSample
    let accent: ModuleAccent

    private var points: [HourlyPoint] {
        Array(sample.forecast.hourly.filter { $0.time >= sample.forecast.current.time }.prefix(48))
    }

    var body: some View {
        GlassCard(tint: accent.primary) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Next 48 hours") {
                    Chip(text: "Scroll for more", color: .secondary, symbol: "arrow.left.and.right")
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HourlyForecastChart(
                        points: points,
                        units: sample.forecast.units,
                        timeZone: sample.forecast.timeZone,
                        accent: accent
                    )
                    .frame(width: max(720, CGFloat(points.count) * 28), height: 150)
                }
                .insetPlate()
            }
        }
    }
}

struct HourlyForecastChart: View {
    let points: [HourlyPoint]
    let units: WeatherUnits
    let timeZone: TimeZone
    let accent: ModuleAccent

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
                let baseline = size.height - 18
                for (index, point) in points.enumerated() {
                    let probability = CGFloat((point.precipitationProbability ?? 0) / 100)
                    let height = max(probability > 0 ? 2 : 0, probability * 22)
                    let rect = CGRect(
                        x: CGFloat(index) * step + step * 0.22,
                        y: baseline - height,
                        width: max(2, step * 0.56),
                        height: height
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 2),
                        with: .linearGradient(
                            Gradient(colors: [Color(hex: 0x60A5FA).opacity(0.9), Color(hex: 0x2563EB).opacity(0.5)]),
                            startPoint: CGPoint(x: 0, y: rect.minY),
                            endPoint: CGPoint(x: 0, y: rect.maxY)
                        )
                    )
                }

                var line = Path()
                var area = Path()
                var first: CGPoint?
                var last: CGPoint?
                for (index, point) in points.enumerated() {
                    guard let temperature = point.temperature else {
                        continue
                    }
                    let x = (CGFloat(index) + 0.5) * step
                    let normalized = CGFloat((temperature - minimum) / spread)
                    // Keep the curve in a band below the hour labels and above the rain bars.
                    let top = size.height - 68
                    let bottom = size.height - 26
                    let y = bottom - normalized * (bottom - top)
                    let location = CGPoint(x: x, y: y)
                    if first == nil {
                        first = location
                        line.move(to: location)
                        area.move(to: CGPoint(x: x, y: bottom + 4))
                        area.addLine(to: location)
                    } else {
                        line.addLine(to: location)
                        area.addLine(to: location)
                    }
                    last = location
                }
                if let first, let last {
                    let floor = size.height - 22
                    area.addLine(to: CGPoint(x: last.x, y: floor))
                    area.addLine(to: CGPoint(x: first.x, y: floor))
                    area.closeSubpath()
                    context.fill(
                        area,
                        with: .linearGradient(
                            Gradient(colors: [accent.secondary.opacity(0.28), accent.primary.opacity(0.02)]),
                            startPoint: CGPoint(x: 0, y: size.height - 68),
                            endPoint: CGPoint(x: 0, y: floor)
                        )
                    )
                }
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: 3))
                    layer.stroke(line, with: .color(accent.secondary.opacity(0.5)), lineWidth: 3.5)
                }
                context.stroke(
                    line,
                    with: .linearGradient(
                        Gradient(colors: [accent.primary, accent.secondary]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: size.width, y: 0)
                    ),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
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
                                    .font(.system(size: 8, weight: .medium).monospacedDigit())
                                    .foregroundStyle(Color(hex: 0x60A5FA))
                            }
                        }
                        .frame(width: 84)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
}

private struct DailyForecastSection: View {
    let sample: WeatherSample
    let accent: ModuleAccent
    let settingsStore: SettingsStore

    var body: some View {
        let daily = sample.forecast.daily
        let minimum = daily.compactMap(\.low).min() ?? 0
        let maximum = daily.compactMap(\.high).max() ?? minimum + 1
        GlassCard {
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel("10-day forecast")
                ForEach(daily) { day in
                    DailyForecastRow(
                        day: day,
                        sample: sample,
                        accent: accent,
                        settingsStore: settingsStore,
                        overallMinimum: minimum,
                        overallMaximum: maximum
                    )
                }
            }
        }
    }
}

private struct DailyForecastRow: View {
    let day: DailyPoint
    let sample: WeatherSample
    let accent: ModuleAccent
    let settingsStore: SettingsStore
    private var timeZone: TimeZone { sample.forecast.timeZone }
    @State private var showsDetails = false
    let overallMinimum: Double
    let overallMaximum: Double
    @State private var isHovering = false

    var body: some View {
        Button { showsDetails.toggle() } label: { row }
            .buttonStyle(.plain)
            .accessibilityLabel("Details for \(WeatherDayDetailView.dateTitle(day.date, timeZone: timeZone))")
            .help("Show daily and hourly forecast details")
            .onChange(of: sample.forecast.location.id) { showsDetails = false }
            .popover(isPresented: $showsDetails, arrowEdge: .trailing) {
                WeatherDayDetailView(day: day, sample: sample, accent: accent, settingsStore: settingsStore)
            }
    }

    private var row: some View {
        HStack(spacing: 9) {
            Text(WeatherValue.weekday(day.date, timeZone: timeZone))
                .font(.callout.weight(.medium))
                .frame(width: 36, alignment: .leading)
            Image(systemName: day.code?.symbolName(isDay: true) ?? "cloud")
                .symbolRenderingMode(.multicolor)
                .frame(width: 22)
            if let probability = day.precipitationProbability, probability > 0 {
                Text(String(format: "%.0f%%", probability))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color(hex: 0x60A5FA))
                    .frame(width: 30, alignment: .trailing)
            } else {
                Text("").frame(width: 30)
            }
            Text(day.low.map { String(format: "%.0f°", $0) } ?? "—")
                .foregroundStyle(.secondary)
                .font(.callout.monospacedDigit())
                .frame(width: 32, alignment: .trailing)
            TemperatureRangeBar(
                low: day.low,
                high: day.high,
                overallMinimum: overallMinimum,
                overallMaximum: overallMaximum
            )
            Text(day.high.map { String(format: "%.0f°", $0) } ?? "—")
                .font(.callout.monospacedDigit())
                .frame(width: 32, alignment: .trailing)
        }
        .overlay(alignment: .trailing) {
            Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary).offset(x: 8)
        }
        .padding(.trailing, 8)
        .contentShape(Rectangle())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(isHovering ? 0.06 : 0))
        )
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
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
            Capsule().fill(Color.primary.opacity(0.08))
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0x22D3EE), Color(hex: 0xFBBF24), Color(hex: 0xF97316)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: max(6, (end - start) * geometry.size.width))
                .offset(x: start * geometry.size.width)
                .shadow(color: Color(hex: 0xFBBF24).opacity(0.35), radius: 3)
        }
        .frame(height: 6)
    }
}

private struct SunMoonSection: View {
    let sample: WeatherSample
    let accent: ModuleAccent

    var body: some View {
        let today = sample.forecast.daily.first
        let phase = MoonPhase.calculate(for: sample.forecast.current.time)
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Sun & Moon")
                HStack(spacing: 8) {
                    StatTile(
                        symbol: "sunrise.fill",
                        label: "Sunrise",
                        value: WeatherValue.time(today?.sunrise, timeZone: sample.forecast.timeZone),
                        tint: .orange,
                        renderingMode: .multicolor
                    )
                    StatTile(
                        symbol: "sunset.fill",
                        label: "Sunset",
                        value: WeatherValue.time(today?.sunset, timeZone: sample.forecast.timeZone),
                        tint: .pink,
                        renderingMode: .multicolor
                    )
                    StatTile(symbol: phase.symbolName, label: "Moon", value: phase.name, tint: accent.primary)
                }
            }
        }
    }
}

private struct AirQualitySection: View {
    let sample: WeatherSample

    var body: some View {
        if let airQuality = sample.airQuality {
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Air quality") {
                        if let value = airQuality.usAQI {
                            Chip(
                                text: WeatherValue.aqiDescription(value), color: WeatherValue.aqiColor(value),
                                symbol: "aqi.medium")
                        }
                    }
                    if let value = airQuality.usAQI {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(value)")
                                .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(WeatherValue.aqiColor(value))
                                .contentTransition(.numericText())
                            Text("US AQI").font(.caption).foregroundStyle(.secondary)
                        }
                        AQIScale(value: value)
                    }
                    HStack(spacing: 8) {
                        if let value = airQuality.pm2_5 {
                            StatTile(
                                symbol: "aqi.medium", label: "PM2.5", value: String(format: "%.1f µg/m³", value),
                                tint: .teal)
                        }
                        if let value = airQuality.pm10 {
                            StatTile(
                                symbol: "aqi.low", label: "PM10", value: String(format: "%.1f µg/m³", value),
                                tint: .teal)
                        }
                    }
                }
            }
        }
    }
}

private struct AQIScale: View {
    let value: Int

    var body: some View {
        GeometryReader { geometry in
            let fraction = min(1, max(0, Double(value) / 300))
            ZStack(alignment: .leading) {
                Capsule().fill(
                    LinearGradient(
                        colors: [.green, .yellow, .orange, .red, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .opacity(0.75)
                Circle()
                    .fill(.white)
                    .frame(width: 10, height: 10)
                    .shadow(color: .black.opacity(0.35), radius: 2)
                    .offset(x: fraction * (geometry.size.width - 10))
            }
        }
        .frame(height: 8)
        .animation(.snappy(duration: 0.4), value: value)
    }
}

private struct WeatherDetailsSection: View {
    let sample: WeatherSample
    let accent: ModuleAccent

    var body: some View {
        let current = sample.forecast.current
        let units = sample.forecast.units
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Details")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    StatTile(
                        symbol: "humidity.fill", label: "Humidity",
                        value: current.humidity.map { String(format: "%.0f%%", $0) } ?? "—", tint: accent.primary)
                    StatTile(
                        symbol: "wind", label: "Wind",
                        value: WeatherValue.wind(current.windSpeed, direction: current.windDirection, units: units),
                        tint: accent.primary)
                    StatTile(
                        symbol: "gauge.with.dots.needle.50percent", label: "Pressure",
                        value: WeatherValue.pressure(current.pressureMSL, units: units), tint: accent.secondary)
                    StatTile(
                        symbol: "cloud.fill", label: "Cloud cover",
                        value: current.cloudCover.map { String(format: "%.0f%%", $0) } ?? "—", tint: .secondary)
                    StatTile(
                        symbol: "drop.fill", label: "Precipitation",
                        value: current.precipitation.map { String(format: "%.2f %@", $0, units.precipitation.symbol) }
                            ?? "—", tint: Color(hex: 0x60A5FA))
                    StatTile(
                        symbol: "wind.snow", label: "Gusts",
                        value: current.windGusts.map { String(format: "%.0f %@", $0, units.windSpeed.symbol) } ?? "—",
                        tint: accent.primary)
                }
            }
        }
    }
}

enum WeatherValue {
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
