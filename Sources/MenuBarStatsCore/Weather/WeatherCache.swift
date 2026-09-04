import Foundation
import OSLog

/// The last successful weather payload persisted for one location.
struct WeatherCacheEntry: Codable, Equatable, Sendable {
    let forecast: Forecast
    let airQuality: AirQuality?
}

/// Stores last-known-good weather data in one file per saved location.
public actor WeatherCache {
    private static let logger = Logger(subsystem: "com.barometer.app", category: "weather-cache")

    private let directory: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Creates a cache in the application-support directory, or an injected test directory.
    public init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directory = directory ?? Self.defaultDirectory(fileManager: fileManager)
    }

    func load(locationID: String) -> WeatherCacheEntry? {
        let fileURL = fileURL(for: locationID)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        do {
            return try decoder.decode(WeatherCacheEntry.self, from: Data(contentsOf: fileURL))
        } catch {
            let message = "Unable to read cached weather for \(locationID): \(String(describing: error))"
            Self.logger.error("\(message, privacy: .public)")
            return nil
        }
    }

    func save(forecast: Forecast, airQuality: AirQuality?) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let entry = WeatherCacheEntry(forecast: forecast, airQuality: airQuality)
        try encoder.encode(entry).write(to: fileURL(for: forecast.location.id), options: .atomic)
    }

    func fileURL(for locationID: String) -> URL {
        directory.appendingPathComponent(Self.cacheKey(for: locationID), isDirectory: false)
    }

    private static func defaultDirectory(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("MenuBarStats", isDirectory: true)
            .appendingPathComponent("weather", isDirectory: true)
    }

    private static func cacheKey(for locationID: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in locationID.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx.json", hash)
    }
}
