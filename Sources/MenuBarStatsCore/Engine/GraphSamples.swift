import Foundation

/// Separates graph history from the full sample used by current-value views.
public protocol HistoryProjecting: Sendable {
    /// Compact value retained by the history buffer.
    associatedtype GraphValue: Sendable

    /// Numeric graph data, excluding process lists and descriptive hardware metadata.
    var graphValue: GraphValue { get }
}

// MARK: - Scalar graphs

/// CPU utilization without per-core or process snapshots.
public struct CPUHistoryValue: Codable, Sendable {
    /// Total CPU utilization in percent.
    public let totalPercent: Double

    /// Creates a compact CPU history value.
    public init(totalPercent: Double) {
        self.totalPercent = totalPercent
    }
}

/// Memory graph readings without process snapshots or unused counters.
public struct MemoryHistoryValue: Sendable {
    /// Used memory as a fraction of physical memory.
    public let usedFraction: Double
    /// Memory pressure in percent.
    public let pressurePercent: Double
}

/// GPU utilization without device metadata or memory counters.
public struct GPUHistoryValue: Codable, Sendable {
    /// Device utilization in percent.
    public let deviceUtilizationPercent: Double

    /// Creates a compact GPU history value.
    public init(deviceUtilizationPercent: Double) {
        self.deviceUtilizationPercent = deviceUtilizationPercent
    }
}

/// Aggregate disk throughput without volume and device metadata.
public struct DiskHistoryValue: Sendable {
    /// Read throughput in bytes per second.
    public let read: Double
    /// Write throughput in bytes per second.
    public let write: Double
}

// MARK: - Network and sensor graphs

/// One network interface's graph data, without addresses or cumulative counters.
public struct NetworkHistoryRate: Sendable {
    /// Stable interface name used by the interface picker.
    public let name: String
    /// Download throughput in bytes per second.
    public let downloadBytesPerSecond: Double
    /// Upload throughput in bytes per second.
    public let uploadBytesPerSecond: Double
}

/// Throughput for each interface, preserving the primary route at sample time.
public struct NetworkHistoryValue: Sendable {
    private let rates: [NetworkHistoryRate]
    private let primaryName: String?

    init(sample: NetworkSample) {
        rates = sample.interfaces.map {
            NetworkHistoryRate(
                name: $0.name,
                downloadBytesPerSecond: $0.downloadBytesPerSecond,
                uploadBytesPerSecond: $0.uploadBytesPerSecond
            )
        }
        primaryName = sample.primary?.name
    }

    /// Resolves a selected interface with the same fallback as the full sample.
    public func interface(named name: String?) -> NetworkHistoryRate? {
        name.flatMap { selected in rates.first { $0.name == selected } }
            ?? rates.first { $0.name == primaryName }
    }
}

/// Sensor values keyed by stable ID, without repeated labels, units, or energy totals.
public struct SensorHistoryValue: Sendable {
    private let ids: [String]
    private let values: [Double]

    init(sample: SensorSample) {
        ids = sample.readings.map(\.id)
        values = sample.readings.map(\.value)
    }

    /// Looks up a reading that existed at sample time; missing readings remain unavailable.
    public func reading(id: String) -> Double? {
        ids.firstIndex(of: id).map { values[$0] }
    }
}

/// Battery charge without adapter, Bluetooth, or health metadata.
public struct BatteryHistoryValue: Sendable {
    /// Battery charge in percent.
    public let chargePercent: Double
}

/// Placeholder for modules whose views use only the latest sample.
public struct NoGraphValue: Sendable {}

// MARK: - Sample projections

extension CPUSample: HistoryProjecting {
    public var graphValue: CPUHistoryValue { CPUHistoryValue(totalPercent: totalPercent) }
}

extension MemorySample: HistoryProjecting {
    public var graphValue: MemoryHistoryValue {
        MemoryHistoryValue(usedFraction: total > 0 ? Double(used) / Double(total) : 0, pressurePercent: pressurePercent)
    }
}

extension GPUSample: HistoryProjecting {
    public var graphValue: GPUHistoryValue { GPUHistoryValue(deviceUtilizationPercent: deviceUtilizationPercent) }
}

extension DiskSample: HistoryProjecting {
    public var graphValue: DiskHistoryValue {
        DiskHistoryValue(
            read: devices.reduce(0) { $0 + $1.readBytesPerSecond },
            write: devices.reduce(0) { $0 + $1.writeBytesPerSecond }
        )
    }
}

extension NetworkSample: HistoryProjecting {
    public var graphValue: NetworkHistoryValue { NetworkHistoryValue(sample: self) }
}

extension SensorSample: HistoryProjecting {
    public var graphValue: SensorHistoryValue { SensorHistoryValue(sample: self) }
}

extension BatterySample: HistoryProjecting {
    public var graphValue: BatteryHistoryValue { BatteryHistoryValue(chargePercent: chargePercent) }
}

extension WeatherSample: HistoryProjecting {
    public var graphValue: NoGraphValue { NoGraphValue() }
}

extension TimeSample: HistoryProjecting {
    public var graphValue: NoGraphValue { NoGraphValue() }
}

extension CombinedSample: HistoryProjecting {
    public var graphValue: NoGraphValue { NoGraphValue() }
}
