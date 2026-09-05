import Foundation
import OSLog

/// A clock used to evaluate weather cache freshness deterministically.
public protocol WeatherDateProvider: Sendable {
    /// Returns the current wall-clock date.
    func now() async -> Date
}

/// Production weather date provider.
public struct SystemWeatherDateProvider: WeatherDateProvider {
    /// Creates a system date provider.
    public init() {}

    public func now() -> Date {
        Date()
    }
}

/// A live or cached weather update ready for presentation.
public struct WeatherSample: Codable, Equatable, Sendable {
    /// Time Barometer produced this sample.
    public let timestamp: Date

    /// Detailed forecast data.
    public let forecast: Forecast

    /// Current air-quality data when available.
    public let airQuality: AirQuality?

    /// Whether the forecast is older than two configured refresh intervals.
    public let isStale: Bool

    /// The refresh error when this sample came from the cache.
    public let refreshError: String?
}

/// Fetches and caches weather for one saved location.
public actor WeatherMonitor: Monitor {
    private static let logger = Logger(subsystem: "com.barometer.app", category: "weather")
    private static let maximumRetryDelaySeconds = 60

    private let location: Location
    private let units: WeatherUnits
    private let refreshInterval: Duration
    private let refreshIntervalSeconds: TimeInterval
    private let client: any WeatherClient
    private let cache: WeatherCache
    private let dateProvider: any WeatherDateProvider
    private var retryDelaySeconds: Int?

    /// Creates a monitor for one saved location.
    public init(
        location: Location,
        units: WeatherUnits,
        refreshInterval: Duration = .seconds(15 * 60),
        client: any WeatherClient = OpenMeteoClient(),
        cache: WeatherCache = WeatherCache(),
        dateProvider: any WeatherDateProvider = SystemWeatherDateProvider()
    ) {
        self.location = location
        self.units = units
        self.refreshInterval = refreshInterval
        refreshIntervalSeconds = max(0, refreshInterval.timeInterval)
        self.client = client
        self.cache = cache
        self.dateProvider = dateProvider
    }

    /// Uses the normal refresh interval or the current retry delay after a cached fallback.
    public var interval: Duration {
        retryDelaySeconds.map(Duration.seconds) ?? refreshInterval
    }

    public nonisolated var isAvailable: Bool {
        true
    }

    /// Fetches fresh weather, falling back to a marked cache entry after network failures.
    public func sample() async throws -> WeatherSample {
        let now = await dateProvider.now()
        do {
            let forecast = try await client.forecast(for: location, units: units)
            let cachedAirQuality = await cache.load(locationID: location.id)?.airQuality
            let airQuality = await fetchAirQuality() ?? cachedAirQuality
            try await cache.save(forecast: forecast, airQuality: airQuality)
            retryDelaySeconds = nil
            Self.logger.debug("Refreshed weather for \(self.location.name, privacy: .public)")
            return WeatherSample(
                timestamp: now,
                forecast: forecast,
                airQuality: airQuality,
                isStale: false,
                refreshError: nil
            )
        } catch {
            let delay = retryDelaySeconds.map { min($0 * 2, Self.maximumRetryDelaySeconds) } ?? 1
            retryDelaySeconds = delay
            guard let cached = await cache.load(locationID: location.id) else {
                throw error
            }
            let age = max(0, now.timeIntervalSince(cached.forecast.fetchedAt))
            let isStale = age >= refreshIntervalSeconds * 2
            let message = "Weather refresh failed for \(location.name); using cache: \(String(describing: error))"
            Self.logger.error("\(message, privacy: .public)")
            return WeatherSample(
                timestamp: now,
                forecast: cached.forecast,
                airQuality: cached.airQuality,
                isStale: isStale,
                refreshError: String(describing: error)
            )
        }
    }

    private func fetchAirQuality() async -> AirQuality? {
        do {
            return try await client.airQuality(for: location)
        } catch {
            let message = "Air-quality refresh failed for \(location.name): \(String(describing: error))"
            Self.logger.error("\(message, privacy: .public)")
            return nil
        }
    }
}

extension Duration {
    fileprivate var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}
