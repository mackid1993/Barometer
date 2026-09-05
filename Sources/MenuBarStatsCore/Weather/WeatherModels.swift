import Foundation

/// A saved weather location with a stable identity.
public struct Location: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let admin: String?
    public let country: String
    public let latitude: Double
    public let longitude: Double
    public let timeZone: String

    /// Creates a saved location.
    public init(
        id: String,
        name: String,
        admin: String?,
        country: String,
        latitude: Double,
        longitude: Double,
        timeZone: String
    ) {
        self.id = id
        self.name = name
        self.admin = admin
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
        self.timeZone = timeZone
    }
}

/// Temperature units supported by Open-Meteo.
public enum TemperatureUnit: String, Codable, CaseIterable, Sendable {
    case celsius
    case fahrenheit

    public var symbol: String { self == .celsius ? "°C" : "°F" }
}

/// Wind-speed units supported by Open-Meteo.
public enum WindSpeedUnit: String, Codable, CaseIterable, Sendable {
    case kilometersPerHour = "kmh"
    case milesPerHour = "mph"
    case metersPerSecond = "ms"
    case knots = "kn"

    public var symbol: String {
        switch self {
        case .kilometersPerHour: "km/h"
        case .milesPerHour: "mph"
        case .metersPerSecond: "m/s"
        case .knots: "kn"
        }
    }
}

/// Pressure display units converted locally from Open-Meteo's hPa values.
public enum PressureUnit: String, Codable, CaseIterable, Sendable {
    case hectopascals
    case inchesOfMercury
    case millimetersOfMercury
}

/// Precipitation units supported by Open-Meteo.
public enum PrecipitationUnit: String, Codable, CaseIterable, Sendable {
    case millimeters = "mm"
    case inches = "inch"

    var queryValue: String { self == .millimeters ? "mm" : "inch" }
    public var symbol: String { self == .millimeters ? "mm" : "in" }
}

/// Independent unit choices used for weather requests and presentation.
public struct WeatherUnits: Codable, Equatable, Sendable {
    public var temperature: TemperatureUnit
    public var windSpeed: WindSpeedUnit
    public var pressure: PressureUnit
    public var precipitation: PrecipitationUnit

    /// Creates a weather unit selection.
    public init(
        temperature: TemperatureUnit,
        windSpeed: WindSpeedUnit,
        pressure: PressureUnit,
        precipitation: PrecipitationUnit
    ) {
        self.temperature = temperature
        self.windSpeed = windSpeed
        self.pressure = pressure
        self.precipitation = precipitation
    }

    /// U.S. customary defaults.
    public static let imperial = WeatherUnits(
        temperature: .fahrenheit,
        windSpeed: .milesPerHour,
        pressure: .inchesOfMercury,
        precipitation: .inches
    )

    /// Common metric defaults.
    public static let metric = WeatherUnits(
        temperature: .celsius,
        windSpeed: .kilometersPerHour,
        pressure: .hectopascals,
        precipitation: .millimeters
    )
}

/// A WMO weather interpretation code with presentation helpers.
public struct WMOCode: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public var description: String {
        switch rawValue {
        case 0: "Clear sky"
        case 1: "Mainly clear"
        case 2: "Partly cloudy"
        case 3: "Overcast"
        case 45: "Fog"
        case 48: "Depositing rime fog"
        case 51: "Light drizzle"
        case 53: "Moderate drizzle"
        case 55: "Dense drizzle"
        case 56: "Light freezing drizzle"
        case 57: "Dense freezing drizzle"
        case 61: "Light rain"
        case 63: "Moderate rain"
        case 65: "Heavy rain"
        case 66: "Light freezing rain"
        case 67: "Heavy freezing rain"
        case 71: "Light snow"
        case 73: "Moderate snow"
        case 75: "Heavy snow"
        case 77: "Snow grains"
        case 80: "Light rain showers"
        case 81: "Moderate rain showers"
        case 82: "Violent rain showers"
        case 85: "Light snow showers"
        case 86: "Heavy snow showers"
        case 95: "Thunderstorm"
        case 96: "Thunderstorm with light hail"
        case 99: "Thunderstorm with heavy hail"
        default: "Unknown conditions"
        }
    }

    /// Returns the closest SF Symbol for this condition and daylight state.
    public func symbolName(isDay: Bool) -> String {
        switch rawValue {
        case 0: isDay ? "sun.max" : "moon.stars"
        case 1, 2: isDay ? "cloud.sun" : "cloud.moon"
        case 3: "cloud"
        case 45, 48: "cloud.fog"
        case 51...57: "cloud.drizzle"
        case 61, 63: "cloud.rain"
        case 65, 80...82: "cloud.heavyrain"
        case 66, 67: "cloud.sleet"
        case 71...77, 85, 86: "cloud.snow"
        case 95: "cloud.bolt"
        case 96, 99: "cloud.bolt.rain"
        default: "questionmark.circle"
        }
    }
}

/// Current detailed weather conditions.
public struct CurrentConditions: Codable, Equatable, Sendable {
    public let time: Date
    public let temperature: Double
    public let apparentTemperature: Double?
    public let humidity: Double?
    public let precipitation: Double?
    public let rain: Double?
    public let showers: Double?
    public let snowfall: Double?
    public let code: WMOCode
    public let isDay: Bool
    public let cloudCover: Double?
    public let pressureMSL: Double?
    public let surfacePressure: Double?
    public let windSpeed: Double?
    public let windDirection: Double?
    public let windGusts: Double?
}

/// One hourly forecast point.
public struct HourlyPoint: Codable, Equatable, Identifiable, Sendable {
    public var id: Date { time }
    public let time: Date
    public let temperature: Double?
    public let apparentTemperature: Double?
    public let precipitationProbability: Double?
    public let precipitation: Double?
    public let code: WMOCode?
    public let windSpeed: Double?
    public let windDirection: Double?
    public let uvIndex: Double?
    public let isDay: Bool?
    public let humidity: Double?
    public let dewPoint: Double?
    public let visibility: Double?
    public let cloudCover: Double?
    /// Additional optional forecast metrics, absent from older caches.
    public var details: HourlyWeatherDetails? = nil
}

/// One daily forecast point.
public struct DailyPoint: Codable, Equatable, Identifiable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let code: WMOCode?
    public let high: Double?
    public let low: Double?
    public let apparentHigh: Double?
    public let apparentLow: Double?
    public let sunrise: Date?
    public let sunset: Date?
    public let uvIndexMax: Double?
    public let precipitation: Double?
    public let precipitationProbability: Double?
    public let windSpeedMax: Double?
    public let windGustsMax: Double?
    /// Additional optional daily summaries and lunar events, absent from older caches.
    public var details: DailyWeatherDetails? = nil
}

/// A complete weather forecast for one saved location.
public struct Forecast: Codable, Equatable, Sendable {
    public let location: Location
    public let units: WeatherUnits
    public let timeZone: TimeZone
    public let current: CurrentConditions
    public let hourly: [HourlyPoint]
    public let daily: [DailyPoint]
    public let fetchedAt: Date
}

/// One result from the Open-Meteo geocoding service.
public struct GeocodingResult: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let admin: String?
    public let country: String
    public let latitude: Double
    public let longitude: Double
    public let timeZone: String
    public let population: Int?

    /// Converts this search result into a saved weather location.
    public var location: Location {
        Location(
            id: "open-meteo-\(id)",
            name: name,
            admin: admin,
            country: country,
            latitude: latitude,
            longitude: longitude,
            timeZone: timeZone
        )
    }
}

/// Current air-quality measurements for one location.
public struct AirQuality: Codable, Equatable, Sendable {
    public let location: Location
    public let time: Date
    public let usAQI: Int?
    public let pm2_5: Double?
    public let pm10: Double?
    public let ozone: Double?
}

/// Eight-phase lunar cycle calculated locally from a known new moon.
public enum MoonPhase: String, Codable, CaseIterable, Sendable {
    case newMoon
    case waxingCrescent
    case firstQuarter
    case waxingGibbous
    case fullMoon
    case waningGibbous
    case lastQuarter
    case waningCrescent

    public var name: String {
        switch self {
        case .newMoon: "New Moon"
        case .waxingCrescent: "Waxing Crescent"
        case .firstQuarter: "First Quarter"
        case .waxingGibbous: "Waxing Gibbous"
        case .fullMoon: "Full Moon"
        case .waningGibbous: "Waning Gibbous"
        case .lastQuarter: "Last Quarter"
        case .waningCrescent: "Waning Crescent"
        }
    }

    public var symbolName: String {
        switch self {
        case .newMoon: "moonphase.new.moon"
        case .waxingCrescent: "moonphase.waxing.crescent"
        case .firstQuarter: "moonphase.first.quarter"
        case .waxingGibbous: "moonphase.waxing.gibbous"
        case .fullMoon: "moonphase.full.moon"
        case .waningGibbous: "moonphase.waning.gibbous"
        case .lastQuarter: "moonphase.last.quarter"
        case .waningCrescent: "moonphase.waning.crescent"
        }
    }

    /// Fraction of the mean synodic cycle since a known new moon, normalized before and after the epoch.
    static func cycleFraction(for date: Date) -> Double {
        let epoch = Date(timeIntervalSince1970: 947_182_440)
        let cycle = date.timeIntervalSince(epoch) / (29.530_588_853 * 86_400)
        return ((cycle.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1))
    }

    /// Calculates the nearest eighth of the synodic lunar month.
    public static func calculate(for date: Date) -> MoonPhase {
        let normalized = cycleFraction(for: date)
        let index = Int((normalized * 8 + 0.5).rounded(.down)) % 8
        return allCases[index]
    }
}
