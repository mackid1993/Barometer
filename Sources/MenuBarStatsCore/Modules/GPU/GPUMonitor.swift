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

    /// Whether an IOAccelerator publishes `PerformanceStatistics`.
    public var isAvailable: Bool {
        acceleratorSource.isAvailable
    }

    /// Creates a runtime-discovered GPU monitor.
    public init(interval: Duration = .seconds(1), acceleratorSource: GPUAcceleratorSource = GPUAcceleratorSource()) {
        self.interval = interval
        self.acceleratorSource = acceleratorSource
        ioReportSource = try? IOReportSource()
        smcSource = try? SMCClient()
    }

    /// Reads current utilization and optional detailed metrics.
    public func sample() async throws -> GPUSample {
        let accelerator = try acceleratorSource.read().max {
            $0.deviceUtilizationPercent < $1.deviceUtilizationPercent
        }
        guard let accelerator else {
            throw GPUMonitorError.noAccelerator
        }

        var frequencyMHz: Double?
        var activePercent: Double?
        var powerWatts: Double?
        var temperatureCelsius: Double?
        if let ioReportSource {
            do {
                let report = try await ioReportSource.sample(over: .milliseconds(250))
                let frequency = report.frequencies.first { $0.kind == .gpu }
                frequencyMHz = frequency?.averageMHz
                activePercent = frequency?.activePercent
                powerWatts = report.power.first { $0.name == "GPU" }?.watts
                temperatureCelsius = report.temperatures.map(\.celsius).max()
            } catch {
                Self.logger.debug("IOReport GPU details unavailable: \(String(describing: error), privacy: .public)")
            }
        }
        if temperatureCelsius == nil, let smcSource {
            temperatureCelsius = try? await Self.smcTemperature(source: smcSource)
        }

        return GPUSample(
            timestamp: Date(),
            name: accelerator.name,
            deviceUtilizationPercent: accelerator.deviceUtilizationPercent,
            rendererUtilizationPercent: accelerator.rendererUtilizationPercent,
            tilerUtilizationPercent: accelerator.tilerUtilizationPercent,
            memoryInUseBytes: accelerator.memoryInUseBytes,
            memoryAllocatedBytes: accelerator.memoryAllocatedBytes,
            driverMemoryInUseBytes: accelerator.driverMemoryInUseBytes,
            frequencyMHz: frequencyMHz,
            activePercent: activePercent,
            powerWatts: powerWatts,
            temperatureCelsius: temperatureCelsius
        )
    }

    private static func smcTemperature(source: SMCClient) async throws -> Double? {
        let values = try await source.sensorValues().compactMap { value -> Double? in
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
