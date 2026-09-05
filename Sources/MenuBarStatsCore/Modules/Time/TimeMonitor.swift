import Foundation
import SystemSources

/// Current wall-clock state and system time zone.
public struct TimeSample: Equatable, Sendable {
    public let timestamp: Date
    public let systemTimeZoneIdentifier: String
    public let calendarAuthorization: CalendarAuthorizationState
    public let upcomingEvents: [CalendarEventSnapshot]

    /// Creates one wall-clock sample.
    public init(
        timestamp: Date = Date(),
        systemTimeZoneIdentifier: String = TimeZone.current.identifier,
        calendarAuthorization: CalendarAuthorizationState = .notDetermined,
        upcomingEvents: [CalendarEventSnapshot] = []
    ) {
        self.timestamp = timestamp
        self.systemTimeZoneIdentifier = systemTimeZoneIdentifier
        self.calendarAuthorization = calendarAuthorization
        self.upcomingEvents = upcomingEvents
    }
}

/// Lightweight monitor for wall-clock status items.
public actor TimeMonitor: Monitor {
    private var showsSeconds: Bool
    private var includesCalendarEvents = false
    private var calendarEventCount = 5
    private let calendarSource: CalendarEventSource

    /// Wall-clock time is available on every supported Mac.
    public var isAvailable: Bool { true }

    /// Creates a time monitor. The coordinator selects a one- or sixty-second scheduler interval.
    public init(showsSeconds: Bool = false, calendarSource: CalendarEventSource = CalendarEventSource()) {
        self.showsSeconds = showsSeconds
        self.calendarSource = calendarSource
    }

    /// Uses one-second ticks only when seconds are visible; otherwise aligns to the next minute.
    public var interval: Duration {
        showsSeconds ? .seconds(1) : .milliseconds(Int64(Self.secondsUntilNextMinute(date: Date()) * 1_000))
    }

    /// Reads the current time and dynamic system time zone.
    public func sample() async -> TimeSample {
        let now = Date()
        let authorization = await calendarSource.authorizationState
        let events = includesCalendarEvents && authorization == .fullAccess
            ? await calendarSource.events(from: now, limit: calendarEventCount)
            : []
        return TimeSample(
            timestamp: now,
            calendarAuthorization: authorization,
            upcomingEvents: events
        )
    }

    /// Changes tick precision for the selected format.
    public func setShowsSeconds(_ value: Bool) {
        showsSeconds = value
    }

    /// Enables or disables event queries without requesting authorization.
    public func setCalendarConfiguration(isEnabled: Bool, count: Int) {
        includesCalendarEvents = isEnabled
        calendarEventCount = min(10, max(1, count))
    }

    /// Requests Calendar access. Call only from a user-initiated action.
    public func requestCalendarAccess() async throws -> CalendarAuthorizationState {
        try await calendarSource.requestFullAccess()
    }

    static func secondsUntilNextMinute(date: Date) -> Double {
        let seconds = date.timeIntervalSinceReferenceDate
        let remainder = seconds.truncatingRemainder(dividingBy: 60)
        return max(0.05, 60 - remainder)
    }
}

/// Deterministic token expansion for custom menu bar clocks.
public enum TimeFormatEngine {
    /// Supported menu bar tokens.
    public static let supportedTokens = [
        "{time}", "{time24}", "{date}", "{weekday}", "{week}", "{day}", "{zone}",
    ]

    /// Expands every supported token for a date and time zone.
    public static func render(
        date: Date,
        timeZone: TimeZone,
        template: String,
        showsSeconds: Bool,
        locale: Locale = .current
    ) -> String {
        let calendar = configuredCalendar(timeZone: timeZone, locale: locale)
        let timeTemplate = showsSeconds ? "jms" : "jm"
        let values = [
            "{time}": formatted(date, template: timeTemplate, timeZone: timeZone, locale: locale),
            "{time24}": formatted(
                date,
                format: showsSeconds ? "HH:mm:ss" : "HH:mm",
                timeZone: timeZone,
                locale: locale
            ),
            "{date}": formatted(date, format: "MMM d", timeZone: timeZone, locale: locale),
            "{weekday}": formatted(date, format: "EEE", timeZone: timeZone, locale: locale),
            "{week}": String(format: "%02d", calendar.component(.weekOfYear, from: date)),
            "{day}": String(format: "%03d", calendar.ordinality(of: .day, in: .year, for: date) ?? 0),
            "{zone}": timeZone.abbreviation(for: date) ?? timeZone.identifier,
        ]
        return values.reduce(template) { result, pair in
            result.replacingOccurrences(of: pair.key, with: pair.value)
        }
    }

    /// Expands tokens to stable, deliberately wide values for menu bar width reservation.
    public static func menuBarPlaceholder(template: String, showsSeconds: Bool) -> String {
        let values = [
            "{time}": showsSeconds ? "00:00:00 AM" : "00:00 AM",
            "{time24}": showsSeconds ? "00:00:00" : "00:00",
            "{date}": "Sep 30",
            "{weekday}": "Wed",
            "{week}": "99",
            "{day}": "999",
            "{zone}": "GMT+00:00",
        ]
        return values.reduce(template) { result, pair in
            result.replacingOccurrences(of: pair.key, with: pair.value)
        }
    }

    private static func formatted(
        _ date: Date,
        template: String,
        timeZone: TimeZone,
        locale: Locale
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: template, options: 0, locale: locale)
        return formatter.string(from: date)
    }

    private static func formatted(
        _ date: Date,
        format: String,
        timeZone: TimeZone,
        locale: Locale
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private static func configuredCalendar(timeZone: TimeZone, locale: Locale) -> Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = timeZone
        calendar.locale = locale
        return calendar
    }
}
