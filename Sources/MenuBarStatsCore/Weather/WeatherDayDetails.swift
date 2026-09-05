import Foundation

/// The selected forecast day, grouped by the location's calendar rather than the computer's time zone.
public struct WeatherDayDetails: Sendable {
    /// Provider summary for this selected date.
    public let day: DailyPoint
    /// Chronologically ordered hours inside the selected local day.
    public let hourly: [HourlyPoint]
    /// Nearest named lunar stage for the selected date.
    public let moonPhase: MoonPhase
    /// Approximate fraction illuminated, from zero to one.
    public let moonIllumination: Double
    /// Whether the local mean-cycle fallback was needed instead of provider lunar data.
    public let usesEstimatedMoonPhase: Bool

    /// Uses local noon for the day's approximate lunar phase and a half-open local-day interval for hours.
    public init(day: DailyPoint, hourly: [HourlyPoint], timeZone: TimeZone) {
        self.day = day
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let interval = calendar.dateInterval(of: .day, for: day.date)
        self.hourly = hourly.filter { point in
            guard let interval else { return false }
            return point.time >= interval.start && point.time < interval.end
        }.sorted { $0.time < $1.time }
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day.date) ?? day.date
        if let cycle = day.details?[.moonPhase], cycle.isFinite, (0...1).contains(cycle) {
            moonPhase = MoonPhase.allCases[Int((cycle * 8 + 0.5).rounded(.down)) % 8]
            moonIllumination = (1 - cos(2 * .pi * cycle)) / 2
            usesEstimatedMoonPhase = false
        } else {
            moonPhase = MoonPhase.calculate(for: noon)
            moonIllumination = MoonPhase.illuminationFraction(for: noon)
            usesEstimatedMoonPhase = true
        }
    }

    /// Available sunrise-to-sunset duration; missing polar-day/night data is not interpreted as zero.
    public var daylightDuration: TimeInterval? {
        if let duration = day.details?[.daylightDuration], duration.isFinite, (0...86_400).contains(duration) {
            return duration
        }
        guard let sunrise = day.sunrise, let sunset = day.sunset, sunset >= sunrise else { return nil }
        return sunset.timeIntervalSince(sunrise)
    }
}

extension MoonPhase {
    /// Approximate illuminated fraction from the same mean synodic cycle used for the phase name.
    public static func illuminationFraction(for date: Date) -> Double {
        (1 - cos(2 * .pi * cycleFraction(for: date))) / 2
    }
}
