import Foundation
import MenuBarStatsCore
import SwiftUI

/// Month calendar, world clocks, and primary-location solar times.
public struct TimeDropdownView: View {
    private let store: ModuleStore<TimeSample>
    private let weatherStore: ModuleStore<WeatherSample>
    private let settingsStore: SettingsStore

    /// Creates the Time dropdown.
    public init(
        store: ModuleStore<TimeSample>,
        weatherStore: ModuleStore<WeatherSample>,
        settingsStore: SettingsStore
    ) {
        self.store = store
        self.weatherStore = weatherStore
        self.settingsStore = settingsStore
    }

    public var body: some View {
        let now = store.latestSample?.timestamp ?? Date()
        let _ = store.revision
        let _ = weatherStore.revision
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.date(now)).font(.headline)
                        Text(TimeZone.current.identifier).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Self.time(now, timeZone: .current))
                        .font(.system(.title2, design: .rounded).monospacedDigit().weight(.semibold))
                }

                MonthCalendar(date: now)

                if !settingsStore.settings.time.worldClockIdentifiers.isEmpty {
                    Divider()
                    Text("WORLD CLOCKS").timeSectionLabel()
                    ForEach(settingsStore.settings.time.worldClockIdentifiers, id: \.self) { identifier in
                        if let timeZone = TimeZone(identifier: identifier) {
                            WorldClockRow(date: now, timeZone: timeZone)
                        }
                    }
                }

                if let daily = weatherStore.latestSample?.forecast.daily.first,
                   daily.sunrise != nil || daily.sunset != nil {
                    Divider()
                    Text("SUN").timeSectionLabel()
                    TimeMetricRow(
                        label: "Sunrise",
                        value: daily.sunrise.map { Self.time($0, timeZone: weatherTimeZone) } ?? "Unavailable"
                    )
                    TimeMetricRow(
                        label: "Sunset",
                        value: daily.sunset.map { Self.time($0, timeZone: weatherTimeZone) } ?? "Unavailable"
                    )
                }
            }
            .padding(14)
        }
        .frame(width: 360, height: 540)
    }

    private var weatherTimeZone: TimeZone {
        weatherStore.latestSample?.forecast.timeZone ?? .current
    }

    private static func time(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }

    private static func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}

private struct MonthCalendar: View {
    let date: Date
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)

    var body: some View {
        let calendar = Calendar.current
        let month = calendar.dateInterval(of: .month, for: date)
        let first = month?.start ?? date
        let dayRange = calendar.range(of: .day, in: .month, for: date) ?? 1..<2
        let leading = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        VStack(spacing: 7) {
            Text(monthTitle).font(.subheadline.weight(.semibold))
            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol).font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(0..<leading, id: \.self) { _ in Color.clear.frame(height: 22) }
                ForEach(Array(dayRange), id: \.self) { day in
                    Text("\(day)")
                        .font(.caption.monospacedDigit())
                        .frame(width: 24, height: 22)
                        .background(day == calendar.component(.day, from: date) ? Color.accentColor : .clear)
                        .foregroundStyle(day == calendar.component(.day, from: date) ? .white : .primary)
                        .clipShape(Circle())
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    private var weekdaySymbols: [String] {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        let offset = Calendar.current.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }
}

private struct WorldClockRow: View {
    let date: Date
    let timeZone: TimeZone

    var body: some View {
        HStack {
            Image(systemName: isDaytime ? "sun.max" : "moon")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(timeZone.localizedName(for: .generic, locale: .current) ?? timeZone.identifier)
                    .lineLimit(1)
                Text(Self.offset(timeZone, date: date)).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Self.value(date, timeZone: timeZone)).monospacedDigit()
        }
        .font(.subheadline)
    }

    private var isDaytime: Bool {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return (7..<19).contains(calendar.component(.hour, from: date))
    }

    private static func value(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }

    private static func offset(_ timeZone: TimeZone, date: Date) -> String {
        let seconds = timeZone.secondsFromGMT(for: date)
        let sign = seconds < 0 ? "−" : "+"
        let absolute = abs(seconds)
        return String(format: "UTC%@%d:%02d", sign, absolute / 3_600, absolute % 3_600 / 60)
    }
}

private struct TimeMetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.subheadline)
    }
}

private extension View {
    func timeSectionLabel() -> some View {
        font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
    }
}
