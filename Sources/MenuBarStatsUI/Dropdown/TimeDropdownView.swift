import Foundation
import MenuBarStatsCore
import SwiftUI
import SystemSources

/// Month calendar, world clocks, and primary-location solar times.
public struct TimeDropdownView: View {
    /// Fixed hosted content width; height follows the content.
    public static let contentSize = CGSize(width: 380, height: 560)

    private let store: ModuleStore<TimeSample>
    private let weatherStore: ModuleStore<WeatherSample>
    private let settingsStore: SettingsStore
    private let requestCalendarAccess: @MainActor () -> Void

    /// Creates the Time dropdown.
    public init(
        store: ModuleStore<TimeSample>,
        weatherStore: ModuleStore<WeatherSample>,
        settingsStore: SettingsStore,
        requestCalendarAccess: @escaping @MainActor () -> Void
    ) {
        self.store = store
        self.weatherStore = weatherStore
        self.settingsStore = settingsStore
        self.requestCalendarAccess = requestCalendarAccess
    }

    public var body: some View {
        let now = store.latestSample?.timestamp ?? Date()
        let _ = store.revision
        let _ = weatherStore.revision
        let accent = ModuleAccent.resolve(settingsStore.settings, module: .time)

        DropdownScaffold(size: Self.contentSize) {
            HeroHeader(
                symbolName: "clock.fill",
                title: Self.date(now),
                subtitle: TimeZone.current.localizedName(for: .generic, locale: .current)
                    ?? TimeZone.current.identifier,
                value: Self.time(now, timeZone: .current),
                accent: accent
            )

            GlassCard(tint: accent.primary) {
                MonthCalendar(date: now, accent: accent)
            }

            if !settingsStore.settings.time.worldClockIdentifiers.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 2) {
                        SectionLabel("World clocks")
                        ForEach(settingsStore.settings.time.worldClockIdentifiers, id: \.self) { identifier in
                            if let timeZone = TimeZone(identifier: identifier) {
                                WorldClockRow(date: now, timeZone: timeZone, accent: accent)
                            }
                        }
                    }
                }
            }

            if let daily = weatherStore.latestSample?.forecast.daily.first,
                daily.sunrise != nil || daily.sunset != nil
            {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Sun") {
                            Text(weatherStore.latestSample?.forecast.location.name ?? "")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 8) {
                            StatTile(
                                symbol: "sunrise.fill",
                                label: "Sunrise",
                                value: daily.sunrise.map { Self.time($0, timeZone: weatherTimeZone) } ?? "—",
                                tint: .orange,
                                renderingMode: .multicolor
                            )
                            StatTile(
                                symbol: "sunset.fill",
                                label: "Sunset",
                                value: daily.sunset.map { Self.time($0, timeZone: weatherTimeZone) } ?? "—",
                                tint: .pink,
                                renderingMode: .multicolor
                            )
                        }
                    }
                }
            }

            if settingsStore.settings.time.showsCalendarEvents {
                GlassCard {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionLabel("Upcoming events")
                        calendarContent(sample: store.latestSample, accent: accent)
                    }
                }
            }
        }
    }

    private var weatherTimeZone: TimeZone {
        weatherStore.latestSample?.forecast.timeZone ?? .current
    }

    @ViewBuilder
    private func calendarContent(sample: TimeSample?, accent: ModuleAccent) -> some View {
        switch sample?.calendarAuthorization ?? .notDetermined {
        case .fullAccess:
            if let events = sample?.upcomingEvents, !events.isEmpty {
                ForEach(events) { event in
                    CalendarEventRow(event: event, accent: accent)
                }
            } else {
                Text("No events in the next 14 days.").font(.caption).foregroundStyle(.secondary)
            }
        case .notDetermined:
            VStack(alignment: .leading, spacing: 6) {
                Text("Calendar access has not been requested.").font(.caption).foregroundStyle(.secondary)
                Button("Allow Calendar Access…", action: requestCalendarAccess)
                    .buttonStyle(.glassProminent)
                    .controlSize(.small)
            }
        case .denied, .restricted, .writeOnly:
            Text(
                "Calendar events are unavailable. Allow full access in "
                    + "System Settings > Privacy & Security > Calendars."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        case .unavailable:
            Text("Calendar events are unavailable on this system.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private static func time(_ date: Date, timeZone: TimeZone) -> String {
        DateFormatterCache.string(from: date, timeStyle: .short, timeZone: timeZone)
    }

    private static func date(_ date: Date) -> String {
        date.formatted(
            Date.VerbatimFormatStyle(
                format: "\(weekday: .wide), \(month: .wide) \(day: .defaultDigits)",
                locale: .current,
                timeZone: .current,
                calendar: .current
            ))
    }
}

private struct CalendarEventRow: View {
    let event: CalendarEventSnapshot
    let accent: ModuleAccent

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accent.gradient)
                .frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.callout).lineLimit(1)
                Text(event.isAllDay ? "All day" : Self.time(event.startDate))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Chip(text: event.calendarTitle, color: accent.secondary)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
    }

    private static func time(_ date: Date) -> String {
        DateFormatterCache.string(from: date, dateStyle: .short, timeStyle: .short)
    }
}

private struct MonthCalendar: View {
    let date: Date
    let accent: ModuleAccent
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)

    var body: some View {
        let calendar = Calendar.current
        let month = calendar.dateInterval(of: .month, for: date)
        let first = month?.start ?? date
        let dayRange = calendar.range(of: .day, in: .month, for: date) ?? 1..<2
        let leading = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let today = calendar.component(.day, from: date)
        VStack(spacing: 8) {
            HStack {
                Text(monthTitle).font(.callout.weight(.semibold))
                Spacer()
                Chip(
                    text: "Week \(calendar.component(.weekOfYear, from: date))", color: accent.primary,
                    symbol: "calendar")
            }
            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                ForEach(0..<leading, id: \.self) { _ in Color.clear.frame(height: 24) }
                ForEach(Array(dayRange), id: \.self) { day in
                    let isToday = day == today
                    let isWeekend = calendar.isDateInWeekend(
                        calendar.date(byAdding: .day, value: day - 1, to: first) ?? first)
                    Text("\(day)")
                        .font(.caption.monospacedDigit().weight(isToday ? .bold : .regular))
                        .frame(width: 26, height: 24)
                        .background {
                            if isToday {
                                Circle()
                                    .fill(accent.gradient)
                                    .shadow(color: accent.primary.opacity(0.55), radius: 6)
                            }
                        }
                        .foregroundStyle(isToday ? Color.white : (isWeekend ? Color.secondary : Color.primary))
                }
            }
        }
    }

    private var monthTitle: String {
        date.formatted(
            Date.VerbatimFormatStyle(
                format: "\(month: .wide) \(year: .defaultDigits)",
                locale: .current,
                timeZone: .current,
                calendar: .current
            ))
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
    let accent: ModuleAccent
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isDaytime ? "sun.max.fill" : "moon.stars.fill")
                .symbolRenderingMode(.multicolor)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(timeZone.localizedName(for: .generic, locale: .current) ?? timeZone.identifier)
                    .font(.callout)
                    .lineLimit(1)
                Text(Self.offset(timeZone, date: date)).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Self.value(date, timeZone: timeZone))
                .font(.system(.callout, design: .rounded).weight(.semibold).monospacedDigit())
                .contentTransition(.numericText())
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(isHovering ? 0.06 : 0))
        )
        .onHover { isHovering = $0 }
    }

    private var isDaytime: Bool {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return (7..<19).contains(calendar.component(.hour, from: date))
    }

    private static func value(_ date: Date, timeZone: TimeZone) -> String {
        DateFormatterCache.string(from: date, timeStyle: .short, timeZone: timeZone)
    }

    private static func offset(_ timeZone: TimeZone, date: Date) -> String {
        let seconds = timeZone.secondsFromGMT(for: date)
        let sign = seconds < 0 ? "−" : "+"
        let absolute = abs(seconds)
        return String(format: "UTC%@%d:%02d", sign, absolute / 3_600, absolute % 3_600 / 60)
    }
}
