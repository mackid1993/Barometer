import AppKit
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
                MonthCalendar(
                    date: now,
                    accent: accent,
                    weekStart: settingsStore.settings.time.calendarWeekStart
                )
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
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }

    private static func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        formatter.timeZone = .current
        return formatter.string(from: date)
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
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct MonthCalendar: View {
    let date: Date
    let accent: ModuleAccent
    let weekStart: CalendarWeekStart
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)
    private let overviewColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)
    private let decadeColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 5)
    @State private var navigation: CalendarNavigation
    @State private var displayMode = CalendarDisplayMode.month

    init(date: Date, accent: ModuleAccent, weekStart: CalendarWeekStart) {
        self.date = date
        self.accent = accent
        self.weekStart = weekStart
        _navigation = State(initialValue: CalendarNavigation(selectedDate: date))
    }

    var body: some View {
        let calendar = configuredCalendar
        let displayedDate = navigation.selectedDate
        let month = calendar.dateInterval(of: .month, for: displayedDate)
        let first = month?.start ?? displayedDate
        let dayRange = calendar.range(of: .day, in: .month, for: displayedDate) ?? 1..<2
        let leading = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let gridItems = CalendarGridItem.items(
            weekdayLabels: CalendarWeekdayLabel.labels(for: calendar),
            leadingCellCount: leading,
            days: dayRange
        )
        VStack(spacing: 8) {
            HStack {
                Button {
                    displayMode.zoomOut()
                } label: {
                    HStack(spacing: 4) {
                        Text(Self.navigationTitle(displayedDate, mode: displayMode))
                        if displayMode != .decade {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                    }
                    .font(.callout.weight(.semibold))
                }
                .buttonStyle(.plain)
                .help(displayMode.zoomOutHelp)
                Spacer()
                if displayMode == .month {
                    Chip(
                        text: "Week \(calendar.component(.weekOfYear, from: displayedDate))", color: accent.primary,
                        symbol: "calendar")
                }
                if displayMode != .month || !calendar.isDate(displayedDate, inSameDayAs: date) {
                    Button("Today") {
                        navigation.reset(to: date)
                        displayMode = .month
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent.primary)
                }
                calendarButton(symbol: "chevron.left", label: displayMode.previousLabel) {
                    movePage(-1, calendar: calendar)
                }
                calendarButton(symbol: "chevron.right", label: displayMode.nextLabel) {
                    movePage(1, calendar: calendar)
                }
            }
            Group {
                switch displayMode {
                case .month:
                    LazyVGrid(columns: columns, spacing: 5) {
                        ForEach(gridItems) { item in
                            switch item {
                            case .weekday(_, let symbol):
                                Text(symbol).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            case .leadingCell:
                                Color.clear.frame(height: 24)
                            case .day(let day):
                                let cellDate = calendar.date(byAdding: .day, value: day - 1, to: first) ?? first
                                let isToday = calendar.isDate(cellDate, inSameDayAs: date)
                                let isSelected = calendar.isDate(cellDate, inSameDayAs: displayedDate)
                                let isWeekend = calendar.isDateInWeekend(cellDate)
                                Button {
                                    navigation.select(day: day, calendar: calendar)
                                } label: {
                                    Text("\(day)")
                                        .font(
                                            .caption.monospacedDigit().weight(
                                                isSelected || isToday ? .bold : .regular
                                            )
                                        )
                                        .frame(width: 26, height: 24)
                                        .background {
                                            if isSelected {
                                                Circle()
                                                    .fill(accent.gradient)
                                                    .shadow(color: accent.primary.opacity(0.55), radius: 6)
                                            } else if isToday {
                                                Circle().stroke(accent.primary, lineWidth: 1)
                                            }
                                        }
                                        .foregroundStyle(
                                            isSelected ? Color.white : (isWeekend ? Color.secondary : Color.primary)
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Self.dayTitle(cellDate))
                            }
                        }
                    }
                case .year:
                    LazyVGrid(columns: overviewColumns, spacing: 10) {
                        ForEach(1...12, id: \.self) { month in
                            let isSelected = month == calendar.component(.month, from: displayedDate)
                            Button(Self.monthName(month, calendar: calendar)) {
                                navigation.select(month: month, calendar: calendar)
                                displayMode = .month
                            }
                            .buttonStyle(.plain)
                            .font(.caption.weight(isSelected ? .bold : .regular))
                            .foregroundStyle(isSelected ? accent.primary : Color.primary)
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(accent.primary.opacity(isSelected ? 0.14 : 0.04))
                            )
                        }
                    }
                case .decade:
                    LazyVGrid(columns: decadeColumns, spacing: 12) {
                        ForEach(Self.yearsInDecade(displayedDate, calendar: calendar), id: \.self) { year in
                            let isSelected = year == calendar.component(.year, from: displayedDate)
                            Button(String(year)) {
                                navigation.select(year: year, calendar: calendar)
                                displayMode = .year
                            }
                            .buttonStyle(.plain)
                            .font(.caption.monospacedDigit().weight(isSelected ? .bold : .regular))
                            .foregroundStyle(isSelected ? accent.primary : Color.primary)
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(accent.primary.opacity(isSelected ? 0.14 : 0.04))
                            )
                        }
                    }
                }
            }
            .frame(minHeight: 174, alignment: .top)
        }
        .background {
            CalendarScrollCapture { action in
                switch action {
                case .weeks(let value):
                    moveVertical(value, calendar: calendar)
                case .months(let value):
                    moveHorizontal(value, calendar: calendar)
                }
            }
        }
        .help("Scroll to browse months. Hold Option while scrolling to move by week.")
    }

    private static func navigationTitle(_ date: Date, mode: CalendarDisplayMode) -> String {
        let formatter = DateFormatter()
        switch mode {
        case .month:
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: date)
        case .year:
            formatter.dateFormat = "yyyy"
            return formatter.string(from: date)
        case .decade:
            let years = yearsInDecade(date, calendar: .current)
            return "\(years.lowerBound)–\(years.upperBound - 1)"
        }
    }

    private static func dayTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }

    private static func monthName(_ month: Int, calendar: Calendar) -> String {
        let symbols = calendar.shortStandaloneMonthSymbols
        return symbols.indices.contains(month - 1) ? symbols[month - 1] : String(month)
    }

    private static func yearsInDecade(_ date: Date, calendar: Calendar) -> Range<Int> {
        let year = calendar.component(.year, from: date)
        let start = year - year % 10
        return start..<(start + 10)
    }

    private var configuredCalendar: Calendar {
        var calendar = Calendar.current
        if let firstWeekday = weekStart.firstWeekday {
            calendar.firstWeekday = firstWeekday
        }
        return calendar
    }

    private func calendarButton(
        symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(label)
        .accessibilityLabel(label)
    }

    private func movePage(_ value: Int, calendar: Calendar) {
        switch displayMode {
        case .month: navigation.moveMonths(value, calendar: calendar)
        case .year: navigation.moveYears(value, calendar: calendar)
        case .decade: navigation.moveYears(value * 10, calendar: calendar)
        }
    }

    private func moveVertical(_ value: Int, calendar: Calendar) {
        switch displayMode {
        case .month: navigation.moveWeeks(value, calendar: calendar)
        case .year: navigation.moveYears(value, calendar: calendar)
        case .decade: navigation.moveYears(value * 10, calendar: calendar)
        }
    }

    private func moveHorizontal(_ value: Int, calendar: Calendar) {
        movePage(value, calendar: calendar)
    }
}

enum CalendarDisplayMode: Equatable {
    case month
    case year
    case decade

    mutating func zoomOut() {
        switch self {
        case .month: self = .year
        case .year: self = .decade
        case .decade: break
        }
    }

    var zoomOutHelp: String {
        switch self {
        case .month: "Show all months in this year"
        case .year: "Show all years in this decade"
        case .decade: "Choose a year"
        }
    }

    var previousLabel: String {
        switch self {
        case .month: "Previous month"
        case .year: "Previous year"
        case .decade: "Previous decade"
        }
    }

    var nextLabel: String {
        switch self {
        case .month: "Next month"
        case .year: "Next year"
        case .decade: "Next decade"
        }
    }
}

struct CalendarNavigation: Equatable {
    private(set) var selectedDate: Date

    mutating func reset(to date: Date) {
        selectedDate = date
    }

    mutating func select(day: Int, calendar: Calendar) {
        guard let monthStart = calendar.dateInterval(of: .month, for: selectedDate)?.start,
              let selected = calendar.date(byAdding: .day, value: day - 1, to: monthStart),
              calendar.isDate(selected, equalTo: monthStart, toGranularity: .month) else {
            return
        }
        selectedDate = selected
    }

    mutating func moveWeeks(_ value: Int, calendar: Calendar) {
        guard value != 0,
              let moved = calendar.date(byAdding: .day, value: value * 7, to: selectedDate) else {
            return
        }
        selectedDate = moved
    }

    mutating func moveMonths(_ value: Int, calendar: Calendar) {
        guard value != 0,
              let monthStart = calendar.dateInterval(of: .month, for: selectedDate)?.start,
              let movedMonth = calendar.date(byAdding: .month, value: value, to: monthStart),
              let dayRange = calendar.range(of: .day, in: .month, for: movedMonth) else {
            return
        }
        let requestedDay = calendar.component(.day, from: selectedDate)
        let day = min(requestedDay, dayRange.count)
        selectedDate = calendar.date(byAdding: .day, value: day - 1, to: movedMonth) ?? movedMonth
    }

    mutating func moveYears(_ value: Int, calendar: Calendar) {
        guard value != 0 else { return }
        moveMonths(value * 12, calendar: calendar)
    }

    mutating func select(month: Int, calendar: Calendar) {
        let year = calendar.component(.year, from: selectedDate)
        select(year: year, month: month, calendar: calendar)
    }

    mutating func select(year: Int, calendar: Calendar) {
        let month = calendar.component(.month, from: selectedDate)
        select(year: year, month: month, calendar: calendar)
    }

    private mutating func select(year: Int, month: Int, calendar: Calendar) {
        guard (1...12).contains(month),
              let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let dayRange = calendar.range(of: .day, in: .month, for: monthStart) else {
            return
        }
        let requestedDay = calendar.component(.day, from: selectedDate)
        selectedDate = calendar.date(
            byAdding: .day,
            value: min(requestedDay, dayRange.count) - 1,
            to: monthStart
        ) ?? monthStart
    }
}

enum CalendarBrowseAction: Equatable {
    case weeks(Int)
    case months(Int)

    static func vertical(steps: Int, optionKey: Bool) -> Self {
        optionKey ? .weeks(steps) : .months(steps)
    }
}

private struct CalendarScrollCapture: NSViewRepresentable {
    let action: @MainActor (CalendarBrowseAction) -> Void

    func makeNSView(context: Context) -> CalendarScrollCaptureView {
        CalendarScrollCaptureView(action: action)
    }

    func updateNSView(_ view: CalendarScrollCaptureView, context: Context) {
        view.action = action
    }

    static func dismantleNSView(_ view: CalendarScrollCaptureView, coordinator: ()) {
        view.stopMonitoring()
    }
}

@MainActor
private final class CalendarScrollCaptureView: NSView {
    var action: @MainActor (CalendarBrowseAction) -> Void
    private var eventMonitor: Any?
    private var accumulatedVerticalDelta: CGFloat = 0
    private var accumulatedHorizontalDelta: CGFloat = 0

    init(action: @escaping @MainActor (CalendarBrowseAction) -> Void) {
        self.action = action
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CalendarScrollCaptureView does not support storyboards")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    func stopMonitoring() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        accumulatedVerticalDelta = 0
        accumulatedHorizontalDelta = 0
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.window === window,
              bounds.contains(convert(event.locationInWindow, from: nil)) else {
            return event
        }
        if event.phase.contains(.began) {
            accumulatedVerticalDelta = 0
            accumulatedHorizontalDelta = 0
        }
        let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 28
        let horizontal = event.scrollingDeltaX * multiplier
        let vertical = event.scrollingDeltaY * multiplier
        if abs(horizontal) > abs(vertical) {
            accumulatedHorizontalDelta += horizontal
            emitSteps(from: &accumulatedHorizontalDelta, threshold: 36, months: true)
        } else {
            accumulatedVerticalDelta += vertical
            emitVerticalSteps(
                from: &accumulatedVerticalDelta,
                threshold: 28,
                optionKey: event.modifierFlags.contains(.option)
            )
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            accumulatedVerticalDelta = 0
            accumulatedHorizontalDelta = 0
        }
        return nil
    }

    private func emitSteps(from accumulator: inout CGFloat, threshold: CGFloat, months: Bool) {
        guard abs(accumulator) >= threshold else { return }
        let magnitude = min(4, Int(abs(accumulator) / threshold))
        let steps = accumulator > 0 ? -magnitude : magnitude
        accumulator -= CGFloat(accumulator > 0 ? magnitude : -magnitude) * threshold
        action(months ? .months(steps) : .weeks(steps))
    }

    private func emitVerticalSteps(from accumulator: inout CGFloat, threshold: CGFloat, optionKey: Bool) {
        guard abs(accumulator) >= threshold else { return }
        let magnitude = min(4, Int(abs(accumulator) / threshold))
        let steps = accumulator > 0 ? -magnitude : magnitude
        accumulator -= CGFloat(accumulator > 0 ? magnitude : -magnitude) * threshold
        action(.vertical(steps: steps, optionKey: optionKey))
    }
}

struct CalendarWeekdayLabel: Identifiable, Equatable {
    let id: Int
    let symbol: String

    static func labels(for calendar: Calendar) -> [Self] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        guard !symbols.isEmpty else { return [] }
        let offset = min(max(0, calendar.firstWeekday - 1), symbols.count - 1)
        let ordered = Array(symbols[offset...] + symbols[..<offset])
        return ordered.enumerated().map { Self(id: $0.offset, symbol: $0.element) }
    }
}

enum CalendarGridItem: Identifiable, Equatable {
    enum ID: Hashable {
        case weekday(Int)
        case leadingCell(Int)
        case day(Int)
    }

    case weekday(column: Int, symbol: String)
    case leadingCell(column: Int)
    case day(Int)

    var id: ID {
        switch self {
        case .weekday(let column, _): .weekday(column)
        case .leadingCell(let column): .leadingCell(column)
        case .day(let day): .day(day)
        }
    }

    static func items(
        weekdayLabels: [CalendarWeekdayLabel],
        leadingCellCount: Int,
        days: Range<Int>
    ) -> [Self] {
        var items = weekdayLabels.map { Self.weekday(column: $0.id, symbol: $0.symbol) }
        items.append(contentsOf: (0..<max(0, leadingCellCount)).map(Self.leadingCell(column:)))
        items.append(contentsOf: days.map(Self.day))
        return items
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
