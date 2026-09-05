import Foundation
import OSLog
import SystemSources

/// Complete graphics utilization, memory, frequency, power, and temperature sample.
public struct GPUSample: Equatable, Sendable {
    public let timestamp: Date
    public let name: String
    public let deviceUtilizationPercent: Double
    public let rendererUtilizationPercent: Double?
    public let tilerUtilizationPercent: Double?
    public let memoryInUseBytes: UInt64?
    public let memoryAllocatedBytes: UInt64?
    public let driverMemoryInUseBytes: UInt64?
    public let frequencyMHz: Double?
    public let activePercent: Double?
    public let powerWatts: Double?
    public let temperatureCelsius: Double?

    /// Creates one normalized GPU sample.
    public init(
        timestamp: Date,
        name: String,
        deviceUtilizationPercent: Double,
        rendererUtilizationPercent: Double? = nil,
        tilerUtilizationPercent: Double? = nil,
        memoryInUseBytes: UInt64? = nil,
        memoryAllocatedBytes: UInt64? = nil,
        driverMemoryInUseBytes: UInt64? = nil,
        frequencyMHz: Double? = nil,
        activePercent: Double? = nil,
        powerWatts: Double? = nil,
        temperatureCelsius: Double? = nil
    ) {
        self.timestamp = timestamp
        self.name = name
        self.deviceUtilizationPercent = deviceUtilizationPercent
        self.rendererUtilizationPercent = rendererUtilizationPercent
        self.tilerUtilizationPercent = tilerUtilizationPercent
        self.memoryInUseBytes = memoryInUseBytes
        self.memoryAllocatedBytes = memoryAllocatedBytes
        self.driverMemoryInUseBytes = driverMemoryInUseBytes
        self.frequencyMHz = frequencyMHz
        self.activePercent = activePercent
        self.powerWatts = powerWatts
        self.temperatureCelsius = temperatureCelsius
    }
}

/// Samples the accelerator directly and enriches it with optional IOReport and SMC values.
public actor GPUMonitor: Monitor {
    public nonisolated let interval: Duration

    private static let logger = Logger(subsystem: "com.barometer.app", category: "gpu")
    private let acceleratorSource: GPUAcceleratorSource
    private let ioReportSource: IOReportSource?
    private let smcSource: SMCClient?
    private var collectsDetails: Bool
    private var lastDetailRefresh: Date?
    private var cachedFrequencyMHz: Double?
    private var cachedActivePercent: Double?
    private var cachedPowerWatts: Double?
    private var cachedTemperatureCelsius: Double?

    /// Whether an IOAccelerator publishes `PerformanceStatistics`.
    public var isAvailable: Bool {
        acceleratorSource.isAvailable
    }

    /// Creates a runtime-discovered GPU monitor.
    public init(
        interval: Duration = .seconds(1),
        acceleratorSource: GPUAcceleratorSource = GPUAcceleratorSource(),
        collectsDetails: Bool = true
    ) {
        self.interval = interval
        self.acceleratorSource = acceleratorSource
        self.collectsDetails = collectsDetails
        ioReportSource = try? IOReportSource()
        smcSource = try? SMCClient()
    }

    /// Enables the slower frequency, power, and temperature sources only while their UI is visible.
    public func setDetailsEnabled(_ enabled: Bool) {
        guard collectsDetails != enabled else { return }
        collectsDetails = enabled
        if enabled {
            lastDetailRefresh = nil
        }
    }

    /// Reads current utilization and optional detailed metrics.
    public func sample() async throws -> GPUSample {
        let accelerator = try acceleratorSource.read().max {
            $0.deviceUtilizationPercent < $1.deviceUtilizationPercent
        }
        guard let accelerator else {
            throw GPUMonitorError.noAccelerator
        }

        let timestamp = Date()
        if Self.shouldRefreshDetails(enabled: collectsDetails, lastRefresh: lastDetailRefresh, now: timestamp) {
            lastDetailRefresh = timestamp
            var refreshedTemperature: Double?
            if let ioReportSource {
                do {
                    let report = try await ioReportSource.sample(over: .milliseconds(250))
                    let frequency = report.frequencies.first { $0.kind == .gpu }
                    cachedFrequencyMHz = frequency?.averageMHz
                    cachedActivePercent = frequency?.activePercent
                    cachedPowerWatts = report.power.first { $0.name == "GPU" }?.watts
                    refreshedTemperature = report.temperatures.map(\.celsius).max()
                } catch {
                    let message = "IOReport GPU details unavailable: \(String(describing: error))"
                    Self.logger.debug("\(message, privacy: .public)")
                }
            }
            if refreshedTemperature == nil, let smcSource {
                refreshedTemperature = try? await Self.smcTemperature(source: smcSource)
            }
            if let refreshedTemperature {
                cachedTemperatureCelsius = refreshedTemperature
            }
        }

        return GPUSample(
            timestamp: timestamp,
            name: accelerator.name,
            deviceUtilizationPercent: accelerator.deviceUtilizationPercent,
            rendererUtilizationPercent: accelerator.rendererUtilizationPercent,
            tilerUtilizationPercent: accelerator.tilerUtilizationPercent,
            memoryInUseBytes: accelerator.memoryInUseBytes,
            memoryAllocatedBytes: accelerator.memoryAllocatedBytes,
            driverMemoryInUseBytes: accelerator.driverMemoryInUseBytes,
            frequencyMHz: cachedFrequencyMHz,
            activePercent: cachedActivePercent,
            powerWatts: cachedPowerWatts,
            temperatureCelsius: cachedTemperatureCelsius
        )
    }

    static func shouldRefreshDetails(
        enabled: Bool = true,
        lastRefresh: Date?,
        now: Date,
        interval: TimeInterval = 10
    ) -> Bool {
        guard enabled else { return false }
        return lastRefresh.map { now.timeIntervalSince($0) >= interval } ?? true
    }

    private static func smcTemperature(source: SMCClient) async throws -> Double? {
        let values = try await source.sensorValues(keyPrefixes: ["Tg", "TG"]).compactMap { value -> Double? in
            guard value.key.hasPrefix("Tg") || value.key.hasPrefix("TG"),
                  let number = value.numericValue,
                  (10...125).contains(number)
            else {
                return nil
            }
            return number
        }
        return values.max()
    }
}

/// GPU monitor failures after the required accelerator source is unavailable.
public enum GPUMonitorError: Error, Sendable {
    case noAccelerator
}
