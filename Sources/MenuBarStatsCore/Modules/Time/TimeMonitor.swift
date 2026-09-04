import Foundation

/// Current wall-clock state and system time zone.
public struct TimeSample: Equatable, Sendable {
    public let timestamp: Date
    public let systemTimeZoneIdentifier: String

    /// Creates one wall-clock sample.
    public init(timestamp: Date = Date(), systemTimeZoneIdentifier: String = TimeZone.current.identifier) {
        self.timestamp = timestamp
        self.systemTimeZoneIdentifier = systemTimeZoneIdentifier
    }
}

/// Lightweight monitor for wall-clock status items.
public actor TimeMonitor: Monitor {
    private var showsSeconds: Bool

    /// Wall-clock time is available on every supported Mac.
    public var isAvailable: Bool { true }

    /// Creates a time monitor. The coordinator selects a one- or sixty-second scheduler interval.
    public init(showsSeconds: Bool = false) {
        self.showsSeconds = showsSeconds
    }

    /// Uses one-second ticks only when seconds are visible; otherwise aligns to the next minute.
    public var interval: Duration {
        showsSeconds ? .seconds(1) : .milliseconds(Int64(Self.secondsUntilNextMinute(date: Date()) * 1_000))
    }

    /// Reads the current time and dynamic system time zone.
    public func sample() -> TimeSample {
        TimeSample()
    }

    /// Changes tick precision for the selected format.
    public func setShowsSeconds(_ value: Bool) {
        showsSeconds = value
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
