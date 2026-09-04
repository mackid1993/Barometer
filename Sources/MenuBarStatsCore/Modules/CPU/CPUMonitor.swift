import Foundation
import SystemSources

/// CPU use for one logical core.
public struct CPUCoreSample: Sendable {
    /// Logical core index.
    public let index: Int

    /// Efficiency, performance, or unknown core kind.
    public let kind: CPUCoreKind

    /// Busy percentage from 0 through 100.
    public let usagePercent: Double
}

/// Process CPU information displayed by the CPU module.
public struct CPUProcessSample: Sendable {
    /// Process identifier.
    public let processIdentifier: pid_t

    /// Process name.
    public let name: String

    /// Executable path when readable.
    public let path: String?

    /// CPU use as a percentage of total machine capacity.
    public let cpuPercent: Double

    /// Effective user identifier owning the process.
    public let userIdentifier: UInt32
}

/// One complete CPU module sample.
public struct CPUSample: Sendable {
    /// Sample timestamp.
    public let timestamp: Date

    /// Total non-idle CPU percentage.
    public let totalPercent: Double

    /// User-mode percentage.
    public let userPercent: Double

    /// System-mode percentage.
    public let systemPercent: Double

    /// Idle percentage.
    public let idlePercent: Double

    /// Nice-priority percentage.
    public let nicePercent: Double

    /// Per-logical-core busy percentages.
    public let perCore: [CPUCoreSample]

    /// 1-, 5-, and 15-minute load averages.
    public let loadAverages: [Double]

    /// Elapsed seconds since boot.
    public let uptime: TimeInterval?

    /// Number of process identifiers returned by libproc.
    public let processCount: Int

    /// Sum of readable per-process thread counts.
    public let threadCount: Int

    /// Processes with the highest recent CPU use.
    public let topProcesses: [CPUProcessSample]
}

/// Samples CPU and process counters and converts cumulative values into rates.
public actor CPUMonitor: Monitor {
    /// Normal CPU sampling interval.
    public nonisolated let interval: Duration

    private let cpuSource: CPUSource
    private let processSource: ProcessSource
    private let topology: CoreTopology
    private var previousTicks: CPUTickSnapshot?

    /// Whether the Mach CPU source is available.
    public var isAvailable: Bool {
        cpuSource.isAvailable
    }

    /// Creates a CPU monitor.
    public init(interval: Duration = .seconds(1)) {
        self.interval = interval
        let source = CPUSource()
        cpuSource = source
        processSource = ProcessSource()
        topology = source.topology()
    }

    /// Collects and calculates one CPU sample.
    public func sample() throws -> CPUSample {
        let currentTicks = try cpuSource.readTicks()
        let usage = Self.calculateUsage(previous: previousTicks, current: currentTicks, topology: topology)
        previousTicks = currentTicks

        let processes = processSource.readProcesses(logicalCPUCount: currentTicks.cores.count)
        let topProcesses = processes.processes
            .sorted { lhs, rhs in
                if lhs.cpuPercent == rhs.cpuPercent {
                    return lhs.physicalFootprint > rhs.physicalFootprint
                }
                return lhs.cpuPercent > rhs.cpuPercent
            }
            .prefix(5)
            .map { process in
                CPUProcessSample(
                    processIdentifier: process.processIdentifier,
                    name: process.name,
                    path: process.path,
                    cpuPercent: process.cpuPercent,
                    userIdentifier: process.userIdentifier
                )
            }

        return CPUSample(
            timestamp: Date(),
            totalPercent: usage.total,
            userPercent: usage.user,
            systemPercent: usage.system,
            idlePercent: usage.idle,
            nicePercent: usage.nice,
            perCore: usage.perCore,
            loadAverages: cpuSource.loadAverages(),
            uptime: cpuSource.uptime(),
            processCount: processes.processCount,
            threadCount: processes.threadCount,
            topProcesses: topProcesses
        )
    }

    private static func calculateUsage(
        previous: CPUTickSnapshot?,
        current: CPUTickSnapshot,
        topology: CoreTopology
    ) -> (total: Double, user: Double, system: Double, idle: Double, nice: Double, perCore: [CPUCoreSample]) {
        guard let previous, previous.cores.count == current.cores.count else {
            let cores = current.cores.indices.map { index in
                CPUCoreSample(
                    index: index,
                    kind: topology.coreKinds.indices.contains(index) ? topology.coreKinds[index] : .unknown,
                    usagePercent: 0
                )
            }
            return (0, 0, 0, 100, 0, cores)
        }

        var totalUser: UInt64 = 0
        var totalSystem: UInt64 = 0
        var totalIdle: UInt64 = 0
        var totalNice: UInt64 = 0
        var perCore: [CPUCoreSample] = []

        for index in current.cores.indices {
            let old = previous.cores[index]
            let new = current.cores[index]
            let user = counterDelta(from: old.user, to: new.user)
            let system = counterDelta(from: old.system, to: new.system)
            let idle = counterDelta(from: old.idle, to: new.idle)
            let nice = counterDelta(from: old.nice, to: new.nice)
            let total = user + system + idle + nice
            let usage = total > 0 ? Double(total - idle) / Double(total) * 100 : 0
            let kind = topology.coreKinds.indices.contains(index) ? topology.coreKinds[index] : .unknown
            perCore.append(CPUCoreSample(index: index, kind: kind, usagePercent: usage))
            totalUser += user
            totalSystem += system
            totalIdle += idle
            totalNice += nice
        }

        let totalTicks = totalUser + totalSystem + totalIdle + totalNice
        guard totalTicks > 0 else {
            return (0, 0, 0, 100, 0, perCore)
        }
        let scale = 100 / Double(totalTicks)
        let idlePercent = Double(totalIdle) * scale
        return (
            total: 100 - idlePercent,
            user: Double(totalUser) * scale,
            system: Double(totalSystem) * scale,
            idle: idlePercent,
            nice: Double(totalNice) * scale,
            perCore: perCore
        )
    }

    private static func counterDelta(from old: UInt64, to new: UInt64) -> UInt64 {
        new >= old ? new - old : UInt64.max - old + new + 1
    }
}
