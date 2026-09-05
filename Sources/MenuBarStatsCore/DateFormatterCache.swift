import Foundation
import Synchronization

/// Process-wide cache of configured DateFormatter instances.
///
/// DateFormatter is expensive to create and is not Sendable, so callers describe the formatter they need with
/// a hashable Configuration and the cache formats or parses inside its lock. Formatters never escape the lock,
/// which keeps the cache safe to use from any isolation domain.
package enum DateFormatterCache {
    /// Everything that distinguishes one configured formatter from another.
    package struct Configuration: Hashable, Sendable {
        /// How the formatter derives its pattern.
        package enum Pattern: Hashable, Sendable {
            /// A literal dateFormat pattern.
            case format(String)
            /// A template passed through setLocalizedDateFormatFromTemplate.
            case localizedTemplate(String)
            /// Locale-driven dateStyle and timeStyle.
            case styles(date: DateFormatter.Style, time: DateFormatter.Style)
        }

        package var pattern: Pattern
        package var timeZone: TimeZone
        package var locale: Locale
        package var calendarIdentifier: Calendar.Identifier?
        package var amSymbol: String?
        package var pmSymbol: String?

        /// Creates a configuration; unset fields keep DateFormatter defaults.
        package init(
            pattern: Pattern,
            timeZone: TimeZone = .current,
            locale: Locale = .current,
            calendarIdentifier: Calendar.Identifier? = nil,
            amSymbol: String? = nil,
            pmSymbol: String? = nil
        ) {
            self.pattern = pattern
            self.timeZone = timeZone
            self.locale = locale
            self.calendarIdentifier = calendarIdentifier
            self.amSymbol = amSymbol
            self.pmSymbol = pmSymbol
        }

        fileprivate func makeFormatter() -> DateFormatter {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = timeZone
            if let calendarIdentifier {
                formatter.calendar = Calendar(identifier: calendarIdentifier)
            }
            if let amSymbol {
                formatter.amSymbol = amSymbol
            }
            if let pmSymbol {
                formatter.pmSymbol = pmSymbol
            }
            switch pattern {
            case .format(let format):
                formatter.dateFormat = format
            case .localizedTemplate(let template):
                formatter.setLocalizedDateFormatFromTemplate(template)
            case .styles(let dateStyle, let timeStyle):
                formatter.dateStyle = dateStyle
                formatter.timeStyle = timeStyle
            }
            return formatter
        }
    }

    private static let formatters = Mutex<[Configuration: DateFormatter]>([:])

    // MARK: - Formatting

    /// Formats a date with the formatter described by configuration.
    package static func string(from date: Date, _ configuration: Configuration) -> String {
        withFormatter(configuration) { $0.string(from: date) }
    }

    /// Formats a date with locale-driven dateStyle and timeStyle.
    package static func string(
        from date: Date,
        dateStyle: DateFormatter.Style = .none,
        timeStyle: DateFormatter.Style = .none,
        timeZone: TimeZone = .current
    ) -> String {
        string(from: date, Configuration(pattern: .styles(date: dateStyle, time: timeStyle), timeZone: timeZone))
    }

    /// Formats a date with a literal dateFormat pattern.
    package static func string(
        from date: Date,
        format: String,
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) -> String {
        string(from: date, Configuration(pattern: .format(format), timeZone: timeZone, locale: locale))
    }

    /// Formats a date with a localized template such as "EEEE MMM d".
    package static func string(
        from date: Date,
        template: String,
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) -> String {
        string(from: date, Configuration(pattern: .localizedTemplate(template), timeZone: timeZone, locale: locale))
    }

    // MARK: - Parsing

    /// Parses a string with the formatter described by configuration.
    package static func date(from string: String, _ configuration: Configuration) -> Date? {
        withFormatter(configuration) { $0.date(from: string) }
    }

    // MARK: - Storage

    private static func withFormatter<Result: Sendable>(
        _ configuration: Configuration,
        _ body: (DateFormatter) -> Result
    ) -> Result {
        formatters.withLock { formatters in
            if let formatter = formatters[configuration] {
                return body(formatter)
            }
            let formatter = configuration.makeFormatter()
            formatters[configuration] = formatter
            return body(formatter)
        }
    }
}
