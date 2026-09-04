import Foundation
import Testing
@testable import MenuBarStatsCore

@Suite("WeatherMonitorTests")
struct WeatherMonitorTests {
    private let boston = Location(
        id: "boston-ma-us",
        name: "Boston",
        admin: "Massachusetts",
        country: "United States",
        latitude: 42.3601,
        longitude: -71.0589,
        timeZone: "America/New_York"
    )

    @Test("successful refresh persists and failed refresh uses cache with exponential retry")
    func cacheFallbackAndRetry() async throws {
        let forecast = try fixtureForecast()
        let airQuality = try OpenMeteoClient.decodeAirQuality(
            try fixture(named: "air-quality-boston"),
            for: boston
        )
        let client = StubWeatherClient(
            forecasts: [.success(forecast), .failure, .failure, .success(forecast)],
            airQuality: airQuality
        )
        let dates = TestWeatherDateProvider(forecast.fetchedAt)
        let cache = WeatherCache(directory: temporaryDirectory())
        let monitor = WeatherMonitor(
            location: boston,
            units: .imperial,
            refreshInterval: .seconds(100),
            client: client,
            cache: cache,
            dateProvider: dates
        )

        let fresh = try await monitor.sample()
        #expect(fresh.isStale == false)
        #expect(fresh.airQuality?.usAQI == 52)
        #expect(await monitor.interval == .seconds(100))

        await dates.set(forecast.fetchedAt.addingTimeInterval(150))
        let cached = try await monitor.sample()
        #expect(cached.isStale == false)
        #expect(cached.refreshError != nil)
        #expect(await monitor.interval == .seconds(1))

        await dates.set(forecast.fetchedAt.addingTimeInterval(201))
        let stale = try await monitor.sample()
        #expect(stale.isStale)
        #expect(stale.forecast == forecast)
        #expect(await monitor.interval == .seconds(2))

        let recovered = try await monitor.sample()
        #expect(recovered.isStale == false)
        #expect(recovered.refreshError == nil)
        #expect(await monitor.interval == .seconds(100))
    }

    @Test("cache filenames cannot escape the weather directory")
    func safeCacheFilename() async {
        let directory = temporaryDirectory()
        let cache = WeatherCache(directory: directory)
        let fileURL = await cache.fileURL(for: "../../Library/Preferences")

        #expect(fileURL.deletingLastPathComponent() == directory)
        #expect(fileURL.pathExtension == "json")
        #expect(fileURL.lastPathComponent.contains("/") == false)
    }

    @Test("failure without a cache is surfaced to the scheduler")
    func noCacheFailure() async throws {
        let client = StubWeatherClient(forecasts: [.failure], airQuality: nil)
        let monitor = WeatherMonitor(
            location: boston,
            units: .imperial,
            client: client,
            cache: WeatherCache(directory: temporaryDirectory())
        )

        await #expect(throws: StubWeatherError.unavailable) {
            try await monitor.sample()
        }
    }

    @Test("network reconnect interrupts the normal interval")
    func refreshOnReconnect() async throws {
        let forecast = try fixtureForecast()
        let client = StubWeatherClient(
            forecasts: [.success(forecast), .success(forecast)],
            airQuality: nil
        )
        let monitor = WeatherMonitor(
            location: boston,
            units: .imperial,
            refreshInterval: .seconds(3_600),
            client: client,
            cache: WeatherCache(directory: temporaryDirectory())
        )
        let network = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(2))
        let session = WeatherMonitoringSession(monitor: monitor, networkChanges: network.stream)
        var samples = session.samples.makeAsyncIterator()

        await session.start()
        _ = try #require(await samples.next())
        network.continuation.yield(false)
        network.continuation.yield(true)
        _ = try #require(await samples.next())
        await session.stop()

        #expect(await client.forecastCount() == 2)
    }

    private func fixtureForecast() throws -> Forecast {
        try OpenMeteoClient.decodeForecast(
            fixture(named: "forecast-boston"),
            for: boston,
            units: .imperial
        )
    }

    private func fixture(named name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BarometerWeatherTests-\(UUID().uuidString)", isDirectory: true)
    }
}

private enum StubWeatherError: Error, Equatable {
    case unavailable
}

private enum ForecastOutcome: Sendable {
    case success(Forecast)
    case failure
}

private actor StubWeatherClient: WeatherClient {
    private var forecasts: [ForecastOutcome]
    private let currentAirQuality: AirQuality?
    private var completedForecasts = 0

    init(forecasts: [ForecastOutcome], airQuality: AirQuality?) {
        self.forecasts = forecasts
        currentAirQuality = airQuality
    }

    func forecast(for location: Location, units: WeatherUnits) throws -> Forecast {
        guard !forecasts.isEmpty else {
            throw StubWeatherError.unavailable
        }
        switch forecasts.removeFirst() {
        case let .success(forecast):
            completedForecasts += 1
            return forecast
        case .failure:
            completedForecasts += 1
            throw StubWeatherError.unavailable
        }
    }

    func geocode(_ query: String) -> [GeocodingResult] {
        []
    }

    func airQuality(for location: Location) throws -> AirQuality {
        guard let currentAirQuality else {
            throw StubWeatherError.unavailable
        }
        return currentAirQuality
    }

    func forecastCount() -> Int {
        completedForecasts
    }
}

private actor TestWeatherDateProvider: WeatherDateProvider {
    private var date: Date

    init(_ date: Date) {
        self.date = date
    }

    func now() -> Date {
        date
    }

    func set(_ date: Date) {
        self.date = date
    }
}
