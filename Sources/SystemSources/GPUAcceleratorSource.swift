import Foundation
import IOKit

/// One graphics accelerator's current IORegistry performance counters.
public struct GPUAcceleratorSnapshot: Equatable, Sendable {
    public let name: String
    public let deviceUtilizationPercent: Double
    public let rendererUtilizationPercent: Double?
    public let tilerUtilizationPercent: Double?
    public let memoryInUseBytes: UInt64?
    public let memoryAllocatedBytes: UInt64?
    public let driverMemoryInUseBytes: UInt64?
}

/// Failures surfaced while enumerating IOAccelerator services.
public enum GPUAcceleratorSourceError: Error, Sendable {
    case matchingServices(kern_return_t)
    case statisticsUnavailable
}

/// Reads runtime-discovered IOAccelerator `PerformanceStatistics` dictionaries.
public struct GPUAcceleratorSource: Sendable {
    // IORegistry service handles are immutable references. The cache owns and releases them once;
    // IORegistry property reads are safe from the monitor actor that owns this source.
    private final class ServiceCache: @unchecked Sendable {
        struct Entry {
            let service: io_service_t
            let name: String
        }

        let entries: [Entry]

        init(entries: [Entry]) {
            self.entries = entries
        }

        deinit {
            for entry in entries {
                IOObjectRelease(entry.service)
            }
        }
    }

    private let serviceCache: ServiceCache?

    /// Whether at least one accelerator publishes a usable device-utilization value.
    public var isAvailable: Bool {
        (try? read().isEmpty) == false
    }

    /// Creates a GPU accelerator source.
    public init() {
        serviceCache = try? Self.discoverServices()
    }

    /// Reads all usable graphics accelerators without assuming a vendor or model identifier.
    public func read() throws -> [GPUAcceleratorSnapshot] {
        guard let serviceCache, !serviceCache.entries.isEmpty else {
            throw GPUAcceleratorSourceError.statisticsUnavailable
        }
        let snapshots = serviceCache.entries.compactMap { entry in
            Self.snapshot(service: entry.service, name: entry.name)
        }
        guard !snapshots.isEmpty else {
            throw GPUAcceleratorSourceError.statisticsUnavailable
        }
        return snapshots.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func discoverServices() throws -> ServiceCache {
        guard let matching = IOServiceMatching("IOAccelerator") else {
            throw GPUAcceleratorSourceError.statisticsUnavailable
        }
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == KERN_SUCCESS else {
            throw GPUAcceleratorSourceError.matchingServices(result)
        }
        defer { IOObjectRelease(iterator) }

        var entries: [ServiceCache.Entry] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            let name = stringProperty(service: service, key: "model")
                ?? stringProperty(service: service, key: "IOClass")
                ?? "GPU"
            entries.append(ServiceCache.Entry(service: service, name: name))
            service = IOIteratorNext(iterator)
        }
        guard !entries.isEmpty else {
            throw GPUAcceleratorSourceError.statisticsUnavailable
        }
        return ServiceCache(entries: entries)
    }

    static func snapshot(name: String, statistics: [String: Any]) -> GPUAcceleratorSnapshot? {
        guard let device = percentage(statistics["Device Utilization %"]) else {
            return nil
        }
        return GPUAcceleratorSnapshot(
            name: name,
            deviceUtilizationPercent: device,
            rendererUtilizationPercent: percentage(statistics["Renderer Utilization %"]),
            tilerUtilizationPercent: percentage(statistics["Tiler Utilization %"]),
            memoryInUseBytes: bytes(statistics["In use system memory"]),
            memoryAllocatedBytes: bytes(statistics["Alloc system memory"]),
            driverMemoryInUseBytes: bytes(statistics["In use system memory (driver)"])
        )
    }

    private static func snapshot(service: io_registry_entry_t, name: String) -> GPUAcceleratorSnapshot? {
        guard let property = IORegistryEntryCreateCFProperty(
            service,
            "PerformanceStatistics" as CFString,
            nil,
            0
        ),
        let statistics = property.takeRetainedValue() as? [String: Any]
        else {
            return nil
        }
        return snapshot(name: name, statistics: statistics)
    }

    private static func percentage(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else {
            return nil
        }
        let result = number.doubleValue
        return result.isFinite && (0...100).contains(result) ? result : nil
    }

    private static func bytes(_ value: Any?) -> UInt64? {
        guard let number = value as? NSNumber else {
            return nil
        }
        let result = number.int64Value
        return result >= 0 ? UInt64(result) : nil
    }

    private static func stringProperty(service: io_registry_entry_t, key: String) -> String? {
        guard let property = IORegistryEntryCreateCFProperty(service, key as CFString, nil, 0) else {
            return nil
        }
        return property.takeRetainedValue() as? String
    }
}
