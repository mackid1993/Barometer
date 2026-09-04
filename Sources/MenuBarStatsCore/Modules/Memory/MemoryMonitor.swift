import Foundation
import SystemSources

/// Process memory information displayed by the Memory module.
public struct MemoryProcessSample: Sendable {
    /// Process identifier.
    public let processIdentifier: Int32

    /// Process name.
    public let name: String

    /// Executable path when readable.
    public let path: String?

    /// Physical memory footprint in bytes.
    public let physicalFootprint: UInt64
}

/// One complete Memory module sample.
public struct MemorySample: Sendable {
    /// Sample timestamp.
    public let timestamp: Date

    /// Installed physical memory in bytes.
    public let total: UInt64

    /// App, wired, and compressed memory in bytes.
    public let used: UInt64

    /// Internal non-purgeable memory in bytes.
    public let app: UInt64

    /// Wired memory in bytes.
    public let wired: UInt64

    /// Compressed memory in bytes.
    public let compressed: UInt64

    /// External and purgeable cached-file memory in bytes.
    public let cached: UInt64

    /// Physical memory not included in used memory, in bytes.
    public let free: UInt64

    /// Memory pressure from 0 through 100.
    public let pressurePercent: Double

    /// Current memory pressure severity.
    public let pressureLevel: MemoryPressureLevel

    /// Swap currently in use, in bytes.
    public let swapUsed: UInt64

    /// Configured swap capacity, in bytes.
    public let swapTotal: UInt64

    /// Processes with the largest physical footprints.
    public let topProcesses: [MemoryProcessSample]
}

/// Samples Mach memory statistics and process footprints.
public actor MemoryMonitor: Monitor {
    /// Normal memory sampling interval.
    public nonisolated let interval: Duration

    private let memorySource: MemorySource
    private let processSource: ProcessSource

    /// Whether Mach and sysctl memory statistics are available.
    public var isAvailable: Bool {
        memorySource.isAvailable
    }

    /// Creates a Memory monitor.
    public init(interval: Duration = .seconds(2)) {
        self.interval = interval
        memorySource = MemorySource()
        processSource = ProcessSource()
    }

    /// Collects one complete Memory sample.
    public func sample() throws -> MemorySample {
        let memory = try memorySource.read()
        let processes = processSource.readProcesses(logicalCPUCount: ProcessInfo.processInfo.processorCount)
        let topProcesses = processes.processes
            .sorted { $0.physicalFootprint > $1.physicalFootprint }
            .prefix(10)
            .map { process in
                MemoryProcessSample(
                    processIdentifier: process.processIdentifier,
                    name: process.name,
                    path: process.path,
                    physicalFootprint: process.physicalFootprint
                )
            }

        return MemorySample(
            timestamp: Date(),
            total: memory.total,
            used: memory.used,
            app: memory.app,
            wired: memory.wired,
            compressed: memory.compressed,
            cached: memory.cached,
            free: memory.free,
            pressurePercent: memory.pressurePercent,
            pressureLevel: memory.pressureLevel,
            swapUsed: memory.swapUsed,
            swapTotal: memory.swapTotal,
            topProcesses: topProcesses
        )
    }
}
