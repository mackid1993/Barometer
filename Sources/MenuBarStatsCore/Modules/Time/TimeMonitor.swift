import Foundation
import Synchronization
import SystemSources

/// Calendar operations used by the Time monitor.
public protocol CalendarEventProviding: Actor, Sendable {
    /// Current Calendar authorization without prompting.
    var authorizationState: CalendarAuthorizationState { get }

    /// Requests full event access following a user action.
    func requestFullAccess() async throws -> CalendarAuthorizationState

    /// Returns upcoming Calendar events.
    func events(from date: Date, limit: Int) -> [CalendarEventSnapshot]
}

extension CalendarEventSource: CalendarEventProviding {}

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
    private let calendarSource: any CalendarEventProviding
    private var cachedCalendarAuthorization: CalendarAuthorizationState?
    private var cachedUpcomingEvents: [CalendarEventSnapshot] = []
    private var nextCalendarRefresh: Date?

    static let calendarRefreshInterval: TimeInterval = 60

    /// Wall-clock time is available on every supported Mac.
    public var isAvailable: Bool { true }

    /// Creates a time monitor. The coordinator selects a one- or sixty-second scheduler interval.
    public init(
        showsSeconds: Bool = false,
        calendarSource: any CalendarEventProviding = CalendarEventSource()
    ) {
        self.showsSeconds = showsSeconds
        self.calendarSource = calendarSource
    }

    /// Uses one-second ticks only when seconds are visible; otherwise aligns to the next minute.
    public var interval: Duration {
        showsSeconds ? .seconds(1) : .milliseconds(Int64(Self.secondsUntilNextMinute(date: Date()) * 1_000))
    }

    /// Reads the current time and dynamic system time zone.
    public func sample() async -> TimeSample {
        await sample(at: Date())
    }

    func sample(at now: Date) async -> TimeSample {
        let shouldRefreshCalendar = cachedCalendarAuthorization == nil
            || nextCalendarRefresh.map { now >= $0 } ?? true
        if shouldRefreshCalendar {
            let authorization = await calendarSource.authorizationState
            cachedCalendarAuthorization = authorization
            cachedUpcomingEvents = includesCalendarEvents && authorization == .fullAccess
                ? await calendarSource.events(from: now, limit: calendarEventCount)
                : []
            nextCalendarRefresh = now.addingTimeInterval(Self.calendarRefreshInterval)
        }
        return TimeSample(
            timestamp: now,
            calendarAuthorization: cachedCalendarAuthorization ?? .unavailable,
            upcomingEvents: cachedUpcomingEvents
        )
    }

    /// Changes tick precision for the selected format.
    public func setShowsSeconds(_ value: Bool) {
        showsSeconds = value
    }

    /// Enables or disables event queries without requesting authorization.
    public func setCalendarConfiguration(isEnabled: Bool, count: Int) {
        let normalizedCount = min(10, max(1, count))
        guard includesCalendarEvents != isEnabled || calendarEventCount != normalizedCount else { return }
        includesCalendarEvents = isEnabled
        calendarEventCount = normalizedCount
        nextCalendarRefresh = nil
    }

    /// Requests Calendar access. Call only from a user-initiated action.
    public func requestCalendarAccess() async throws -> CalendarAuthorizationState {
        let authorization = try await calendarSource.requestFullAccess()
        cachedCalendarAuthorization = authorization
        nextCalendarRefresh = nil
        return authorization
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
        replacingTokens(in: template) { token in
            switch token {
            case "{time}":
                formatted(
                    date,
                    template: showsSeconds ? "jms" : "jm",
                    timeZone: timeZone,
                    locale: locale
                )
            case "{time24}":
                formatted(
                    date,
                    format: showsSeconds ? "HH:mm:ss" : "HH:mm",
                    timeZone: timeZone,
                    locale: locale
                )
            case "{date}":
                formatted(date, format: "MMM d", timeZone: timeZone, locale: locale)
            case "{weekday}":
                formatted(date, format: "EEE", timeZone: timeZone, locale: locale)
            case "{week}":
                String(format: "%02d", configuredCalendar(timeZone: timeZone, locale: locale)
                    .component(.weekOfYear, from: date))
            case "{day}":
                String(format: "%03d", configuredCalendar(timeZone: timeZone, locale: locale)
                    .ordinality(of: .day, in: .year, for: date) ?? 0)
            case "{zone}":
                timeZone.abbreviation(for: date) ?? timeZone.identifier
            default:
                token
            }
        }
    }

    static func replacingTokens(
        in template: String,
        value: (String) -> String
    ) -> String {
        var result = template
        for token in supportedTokens where result.contains(token) {
            result = result.replacingOccurrences(of: token, with: value(token))
        }
        return result
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
        cachedFormatted(
            date,
            key: FormatterKey(locale: locale.identifier, timeZone: timeZone.identifier, format: "template:\(template)"),
            locale: locale,
            timeZone: timeZone
        ) { DateFormatter.dateFormat(fromTemplate: template, options: 0, locale: locale) }
    }

    private static func formatted(
        _ date: Date,
        format: String,
        timeZone: TimeZone,
        locale: Locale
    ) -> String {
        cachedFormatted(
            date,
            key: FormatterKey(locale: locale.identifier, timeZone: timeZone.identifier, format: "format:\(format)"),
            locale: locale,
            timeZone: timeZone
        ) { format }
    }

    private struct FormatterKey: Hashable {
        let locale: String
        let timeZone: String
        let format: String
    }

    private static let formatterCache = Mutex<[FormatterKey: DateFormatter]>([:])

    private static func cachedFormatted(
        _ date: Date,
        key: FormatterKey,
        locale: Locale,
        timeZone: TimeZone,
        format: () -> String?
    ) -> String {
        formatterCache.withLock { cache in
            if let formatter = cache[key] {
                return formatter.string(from: date)
            }
            if cache.count >= 32 {
                cache.removeAll(keepingCapacity: true)
            }
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = timeZone
            formatter.dateFormat = format()
            cache[key] = formatter
            return formatter.string(from: date)
        }
    }

    private static func configuredCalendar(timeZone: TimeZone, locale: Locale) -> Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = timeZone
        calendar.locale = locale
        return calendar
    }
}
