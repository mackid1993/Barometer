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
    private let notificationFeed: NotificationFeed?
    private let requestCalendarAccess: @MainActor () -> Void
    private let selectCalendarDate: @MainActor (Date) -> Void
    @State private var selectedCalendarDate: Date?

    /// Creates the Time dropdown.
    public init(
        store: ModuleStore<TimeSample>,
        weatherStore: ModuleStore<WeatherSample>,
        settingsStore: SettingsStore,
        notificationFeed: NotificationFeed? = nil,
        requestCalendarAccess: @escaping @MainActor () -> Void,
        selectCalendarDate: @escaping @MainActor (Date) -> Void = { _ in }
    ) {
        self.store = store
        self.weatherStore = weatherStore
        self.settingsStore = settingsStore
        self.notificationFeed = notificationFeed
        self.requestCalendarAccess = requestCalendarAccess
        self.selectCalendarDate = selectCalendarDate
        _selectedCalendarDate = State(initialValue: store.latestSample?.selectedCalendarDate)
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

            ForEach(settingsStore.settings.time.dropdownSectionOrder, id: \.self) { section in
                sectionCard(section, now: now, accent: accent)
            }
        }
    }

    /// One card of the dropdown, or nothing when its content is turned off or empty.
    @ViewBuilder
    private func sectionCard(_ section: TimeDropdownSection, now: Date, accent: ModuleAccent) -> some View {
        switch section {
        case .calendar:
            GlassCard(tint: accent.primary) {
                MonthCalendar(
                    date: now,
                    accent: accent,
                    weekStart: settingsStore.settings.time.calendarWeekStart,
                    selectedDate: $selectedCalendarDate,
                    selectDate: { selectedDate in
                        selectCalendarDate(selectedDate)
                    }
                )
            }
        case .dayEvents:
            if settingsStore.settings.time.showsCalendarEvents,
               let selectedCalendarDate {
                GlassCard(tint: accent.primary) {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionLabel(Self.selectedDayTitle(selectedCalendarDate)) {
                            Button("Clear") {
                                self.selectedCalendarDate = nil
                            }
                            .buttonStyle(.plain)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(accent.primary)
                        }
                        selectedDayCalendarContent(
                            sample: store.latestSample,
                            selectedDate: selectedCalendarDate,
                            accent: accent
                        )
                    }
                }
            }
        case .notifications:
            if settingsStore.settings.time.showsNotifications, let notificationFeed {
                GlassCard(tint: accent.primary) {
                    NotificationListView(feed: notificationFeed, accent: accent, now: now)
                }
            }
        case .worldClocks:
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
        case .sun:
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
        case .upcomingEvents:
            if settingsStore.settings.time.showsCalendarEvents {
                GlassCard {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionLabel("Upcoming events")
                        upcomingCalendarContent(
                            sample: store.latestSample,
                            excluding: selectedCalendarDate,
                            accent: accent
                        )
                    }
                }
            }
        }
    }

    private var weatherTimeZone: TimeZone {
        weatherStore.latestSample?.forecast.timeZone ?? .current
    }

    @ViewBuilder
    private func upcomingCalendarContent(
        sample: TimeSample?,
        excluding selectedDate: Date?,
        accent: ModuleAccent
    ) -> some View {
        switch sample?.calendarAuthorization ?? .notDetermined {
        case .fullAccess:
            let selectedIDs: Set<String> = if let selectedDate,
                                              let loadedDate = sample?.selectedCalendarDate,
                                              Calendar.current.isDate(loadedDate, inSameDayAs: selectedDate) {
                Set(sample?.selectedDayEvents.map(\.id) ?? [])
            } else {
                []
            }
            let events = sample?.upcomingEvents.filter { !selectedIDs.contains($0.id) } ?? []
            if !events.isEmpty {
                ForEach(events) { event in
                    CalendarEventRow(event: event, accent: accent)
                }
            } else {
                Text(selectedIDs.isEmpty ? "No events in the next 14 days." : "No other upcoming events.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    @ViewBuilder
    private func selectedDayCalendarContent(
        sample: TimeSample?,
        selectedDate: Date,
        accent: ModuleAccent
    ) -> some View {
        switch sample?.calendarAuthorization ?? .notDetermined {
        case .fullAccess:
            if let loadedDate = sample?.selectedCalendarDate,
               Calendar.current.isDate(loadedDate, inSameDayAs: selectedDate) {
                if let events = sample?.selectedDayEvents, !events.isEmpty {
                    ForEach(events) { event in
                        CalendarEventRow(event: event, accent: accent)
                    }
                } else {
                    Text("No events on this day.").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Loading events…")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
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

    private static func selectedDayTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        formatter.timeZone = .current
        return "Events on \(formatter.string(from: date))"
    }
}

/// The notifications waiting in Notification Center, newest first.
private struct NotificationListView: View {
    let feed: NotificationFeed
    let accent: ModuleAccent
    let now: Date

    /// Rows shown before the list is summarized, keeping the panel within its scroll budget.
    static let visibleLimit = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel("Notifications") {
                if !feed.notifications.isEmpty {
                    HStack(spacing: 8) {
                        Chip(text: "\(feed.notifications.count)", color: accent.secondary)
                        Button("Clear All") { feed.clearAll() }
                            .buttonStyle(.plain)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(accent.primary)
                            .help("Hide every notification from this list")
                    }
                }
            }
            switch feed.snapshot?.access {
            case nil:
                Text("Reading notifications…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            case .fullDiskAccessRequired?:
                Text("Barometer needs Full Disk Access to list notifications. Allow it in System Settings > "
                    + "Privacy & Security > Full Disk Access.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                Button("Open Full Disk Access Settings…") { NotificationAccessSettings.open() }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent.primary)
                    .padding(.horizontal, 4)
            case .unavailable?:
                Text("Notifications are unavailable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            case .available?:
                let notifications = feed.notifications
                if notifications.isEmpty {
                    Text("No notifications")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                } else {
                    ForEach(notifications.prefix(Self.visibleLimit)) { notification in
                        NotificationRow(notification: notification, now: now, dismiss: { feed.dismiss(notification) })
                    }
                    if notifications.count > Self.visibleLimit {
                        Text("\(notifications.count - Self.visibleLimit) more in Notification Center")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }
                }
            }
        }
    }
}

/// One notification: the sending application's icon, title, text, and age.
///
/// Clicking goes where the notification points: a finished download is revealed in the file viewer,
/// anything else activates the application. Hovering reveals a clear button for this one row.
private struct NotificationRow: View {
    let notification: DeliveredNotification
    let now: Date
    let dismiss: () -> Void
    @Environment(\.menuDetailActions) private var menuDetailActions
    @State private var isHovering = false

    var body: some View {
        Button {
            menuDetailActions?.closeDropdown()
            NotificationRouter.open(NotificationRouter.destination(for: notification))
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(nsImage: NotificationApplicationResolver.icon(bundleIdentifier: notification.applicationIdentifier))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 18, height: 18)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(notification.title)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if isHovering {
                            Button(action: dismiss) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Clear this notification")
                            .accessibilityLabel("Clear")
                        } else {
                            Text(NotificationAgeFormatter.string(from: notification.date, now: now))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    if let subtitle = notification.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let body = notification.body {
                        Text(body)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.06 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(helpText)
    }
}

extension NotificationRow {
    fileprivate var helpText: String {
        NotificationRouter.label(for: NotificationRouter.destination(for: notification))
    }
}

/// Short ages for notification rows.
enum NotificationAgeFormatter {
    static func string(from date: Date, now: Date, calendar: Calendar = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if calendar.isDate(date, inSameDayAs: now) { return "\(Int(seconds / 3600))h" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday)
        {
            return "Yesterday"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter.string(from: date)
    }
}

/// Opens the Full Disk Access pane of System Settings.
enum NotificationAccessSettings {
    @MainActor
    static func open() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

/// Icons and names for the applications behind notifications, cached per bundle identifier.
@MainActor
enum NotificationApplicationResolver {
    private static var icons: [String: NSImage] = [:]
    private static var names: [String: String] = [:]

    /// Daemon-sent system notifications carry a `_SYSTEM_CENTER_:` prefix; the icon and name come
    /// from the real bundle behind it, or from System Settings when there is no application.
    static func applicationBundleIdentifier(_ identifier: String) -> String {
        let prefix = "_SYSTEM_CENTER_:"
        return identifier.hasPrefix(prefix) ? String(identifier.dropFirst(prefix.count)) : identifier
    }

    static func icon(bundleIdentifier rawIdentifier: String) -> NSImage {
        let bundleIdentifier = applicationBundleIdentifier(rawIdentifier)
        if let cached = icons[bundleIdentifier] { return cached }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? (bundleIdentifier.hasPrefix("com.apple.")
                ? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences")
                    .map { NSWorkspace.shared.icon(forFile: $0.path) }
                : nil)
            ?? NSImage(systemSymbolName: "app.badge", accessibilityDescription: "Application")
            ?? NSImage()
        let thumbnail = ProcessIconResolver.thumbnail(icon, side: 18)
        if icons.count > 64 { icons.removeAll() }
        icons[bundleIdentifier] = thumbnail
        return thumbnail
    }

    static func name(bundleIdentifier rawIdentifier: String) -> String {
        let bundleIdentifier = applicationBundleIdentifier(rawIdentifier)
        if let cached = names[bundleIdentifier] { return cached }
        let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
            .map { FileManager.default.displayName(atPath: $0.path) }
            .map { $0.hasSuffix(".app") ? String($0.dropLast(4)) : $0 }
            ?? bundleIdentifier
        names[bundleIdentifier] = name
        return name
    }

    static func open(bundleIdentifier rawIdentifier: String) {
        let bundleIdentifier = applicationBundleIdentifier(rawIdentifier)
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            if let settings = URL(string: "x-apple.systempreferences:") { NSWorkspace.shared.open(settings) }
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
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
                Text(CalendarEventScheduleFormatter.string(for: event))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Chip(text: event.calendarTitle, color: accent.secondary)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
    }
}

enum CalendarEventScheduleFormatter {
    static func string(
        for event: CalendarEventSnapshot,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.timeZone = timeZone
        dateFormatter.dateFormat = "EEE, MMM d"
        let date = dateFormatter.string(from: event.startDate)
        guard !event.isAllDay else { return "\(date) • All day" }

        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.timeZone = timeZone
        timeFormatter.timeStyle = .short
        return "\(date) • \(timeFormatter.string(from: event.startDate))"
    }
}

private struct MonthCalendar: View {
    let date: Date
    let accent: ModuleAccent
    let weekStart: CalendarWeekStart
    let selectDate: @MainActor (Date) -> Void
    @Binding var selectedDate: Date?
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)
    private let overviewColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)
    private let decadeColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 5)
    @State private var navigation: CalendarNavigation
    @State private var displayMode = CalendarDisplayMode.month
    @State private var monthTransitionDirection = 1

    init(
        date: Date,
        accent: ModuleAccent,
        weekStart: CalendarWeekStart,
        selectedDate: Binding<Date?>,
        selectDate: @escaping @MainActor (Date) -> Void
    ) {
        self.date = date
        self.accent = accent
        self.weekStart = weekStart
        self.selectDate = selectDate
        _selectedDate = selectedDate
        _navigation = State(initialValue: CalendarNavigation(selectedDate: date))
    }

    var body: some View {
        let calendar = configuredCalendar
        let visibleDate = navigation.visibleDate
        let month = calendar.dateInterval(of: .month, for: visibleDate)
        let first = month?.start ?? visibleDate
        let dayRange = calendar.range(of: .day, in: .month, for: visibleDate) ?? 1..<2
        let leading = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let gridItems = CalendarGridItem.items(
            weekdayLabels: CalendarWeekdayLabel.labels(for: calendar),
            leadingCellCount: leading,
            days: dayRange
        )
        VStack(spacing: 8) {
            HStack {
                Button {
                    withAnimation(.smooth(duration: 0.18)) {
                        displayMode.zoomOut()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(Self.navigationTitle(visibleDate, mode: displayMode))
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
                        text: "Week \(calendar.component(.weekOfYear, from: visibleDate))", color: accent.primary,
                        symbol: "calendar")
                }
                if displayMode != .month || !calendar.isDate(visibleDate, inSameDayAs: date) {
                    Button("Today") {
                        monthTransitionDirection = date < visibleDate ? -1 : 1
                        withAnimation(.smooth(duration: 0.18)) {
                            navigation.reset(to: date)
                            selectedDate = date
                            displayMode = .month
                        }
                        selectDate(date)
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
                            case .trailingCell:
                                Color.clear.frame(height: 24)
                            case .day(let day):
                                let cellDate = calendar.date(byAdding: .day, value: day - 1, to: first) ?? first
                                let isToday = calendar.isDate(cellDate, inSameDayAs: date)
                                let isSelected = selectedDate.map {
                                    calendar.isDate(cellDate, inSameDayAs: $0)
                                } ?? false
                                let isWeekend = calendar.isDateInWeekend(cellDate)
                                Button {
                                    withAnimation(.smooth(duration: 0.12)) {
                                        selectedDate = cellDate
                                    }
                                    selectDate(cellDate)
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
                    .id(Self.monthIdentity(visibleDate, calendar: calendar))
                    .transition(monthTransition)
                case .year:
                    LazyVGrid(columns: overviewColumns, spacing: 10) {
                        ForEach(1...12, id: \.self) { month in
                            let isSelected = month == calendar.component(.month, from: visibleDate)
                            Button(Self.monthName(month, calendar: calendar)) {
                                withAnimation(.smooth(duration: 0.18)) {
                                    navigation.select(month: month, calendar: calendar)
                                    displayMode = .month
                                }
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
                        ForEach(Self.yearsInDecade(visibleDate, calendar: calendar), id: \.self) { year in
                            let isSelected = year == calendar.component(.year, from: visibleDate)
                            Button(String(year)) {
                                withAnimation(.smooth(duration: 0.18)) {
                                    navigation.select(year: year, calendar: calendar)
                                    displayMode = .year
                                }
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
            .frame(height: 198, alignment: .top)
            .clipped()
        }
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

    private static func monthIdentity(_ date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.year, .month], from: date)
        return (components.year ?? 0) * 100 + (components.month ?? 0)
    }

    private var monthTransition: AnyTransition {
        let incoming: Edge = monthTransitionDirection < 0 ? .leading : .trailing
        let outgoing: Edge = monthTransitionDirection < 0 ? .trailing : .leading
        return .asymmetric(
            insertion: .move(edge: incoming).combined(with: .opacity),
            removal: .move(edge: outgoing).combined(with: .opacity)
        )
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
        monthTransitionDirection = value < 0 ? -1 : 1
        withAnimation(.smooth(duration: 0.18)) {
            switch displayMode {
            case .month: navigation.moveMonths(value, calendar: calendar)
            case .year: navigation.moveYears(value, calendar: calendar)
            case .decade: navigation.moveYears(value * 10, calendar: calendar)
            }
        }
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
    private(set) var visibleDate: Date

    init(selectedDate: Date) {
        visibleDate = selectedDate
    }

    mutating func reset(to date: Date) {
        visibleDate = date
    }

    mutating func moveMonths(_ value: Int, calendar: Calendar) {
        guard value != 0,
              let monthStart = calendar.dateInterval(of: .month, for: visibleDate)?.start,
              let movedMonth = calendar.date(byAdding: .month, value: value, to: monthStart),
              let dayRange = calendar.range(of: .day, in: .month, for: movedMonth) else {
            return
        }
        let requestedDay = calendar.component(.day, from: visibleDate)
        let day = min(requestedDay, dayRange.count)
        visibleDate = calendar.date(byAdding: .day, value: day - 1, to: movedMonth) ?? movedMonth
    }

    mutating func moveYears(_ value: Int, calendar: Calendar) {
        guard value != 0 else { return }
        moveMonths(value * 12, calendar: calendar)
    }

    mutating func select(month: Int, calendar: Calendar) {
        let year = calendar.component(.year, from: visibleDate)
        select(year: year, month: month, calendar: calendar)
    }

    mutating func select(year: Int, calendar: Calendar) {
        let month = calendar.component(.month, from: visibleDate)
        select(year: year, month: month, calendar: calendar)
    }

    private mutating func select(year: Int, month: Int, calendar: Calendar) {
        guard (1...12).contains(month),
              let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let dayRange = calendar.range(of: .day, in: .month, for: monthStart) else {
            return
        }
        let requestedDay = calendar.component(.day, from: visibleDate)
        visibleDate = calendar.date(
            byAdding: .day,
            value: min(requestedDay, dayRange.count) - 1,
            to: monthStart
        ) ?? monthStart
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
        case trailingCell(Int)
    }

    case weekday(column: Int, symbol: String)
    case leadingCell(column: Int)
    case day(Int)
    case trailingCell(column: Int)

    var id: ID {
        switch self {
        case .weekday(let column, _): .weekday(column)
        case .leadingCell(let column): .leadingCell(column)
        case .day(let day): .day(day)
        case .trailingCell(let column): .trailingCell(column)
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
        let occupiedDayCells = max(0, leadingCellCount) + days.count
        let trailingCellCount = max(0, 42 - occupiedDayCells)
        items.append(contentsOf: (0..<trailingCellCount).map(Self.trailingCell(column:)))
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
