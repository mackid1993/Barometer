import Darwin
import Foundation

/// Cumulative Mach scheduler ticks for one logical CPU.
public struct CPUCoreTicks: Sendable {
    /// User-mode ticks.
    public let user: UInt64

    /// System-mode ticks.
    public let system: UInt64

    /// Idle ticks.
    public let idle: UInt64

    /// Nice-priority ticks.
    public let nice: UInt64
}

/// Cumulative ticks for every logical CPU.
public struct CPUTickSnapshot: Sendable {
    /// Per-core counters in logical CPU order.
    public let cores: [CPUCoreTicks]
}

/// Apple Silicon core kind used for per-core labeling.
public enum CPUCoreKind: String, Sendable {
    case efficiency
    case performance
    case unknown
}

/// Static topology of the logical CPUs.
public struct CoreTopology: Sendable {
    /// Kind for each logical CPU, in scheduler order.
    public let coreKinds: [CPUCoreKind]

    /// Number of performance logical CPUs.
    public let performanceCoreCount: Int

    /// Number of efficiency logical CPUs.
    public let efficiencyCoreCount: Int
}

/// Reads CPU counters and machine-wide CPU metadata from Mach and sysctl.
public struct CPUSource: Sendable {
    /// Whether Mach reports at least one logical processor.
    public var isAvailable: Bool {
        ProcessInfo.processInfo.processorCount > 0
    }

    /// Creates a CPU source.
    public init() {}

    /// Reads cumulative scheduler ticks for every logical CPU.
    public func readTicks() throws -> CPUTickSnapshot {
        var processorCount: natural_t = 0
        var processorInfo: processor_info_array_t?
        var processorInfoCount: mach_msg_type_number_t = 0
        // mach_host_self() returns a send right and adds a user reference to it every call. This
        // runs once a second for the life of the process, so the reference has to be given back.
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = host_processor_info(
            host,
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &processorInfo,
            &processorInfoCount
        )
        guard result == KERN_SUCCESS, let processorInfo else {
            throw CPUSourceError.machError(result)
        }

        defer {
            let byteCount = vm_size_t(processorInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: processorInfo)), byteCount)
        }

        let values = UnsafeBufferPointer(start: processorInfo, count: Int(processorInfoCount))
        let stateCount = Int(CPU_STATE_MAX)
        let cores = (0..<Int(processorCount)).map { coreIndex in
            let base = coreIndex * stateCount
            return CPUCoreTicks(
                user: UInt64(values[base + Int(CPU_STATE_USER)]),
                system: UInt64(values[base + Int(CPU_STATE_SYSTEM)]),
                idle: UInt64(values[base + Int(CPU_STATE_IDLE)]),
                nice: UInt64(values[base + Int(CPU_STATE_NICE)])
            )
        }
        return CPUTickSnapshot(cores: cores)
    }

    /// Reads performance and efficiency logical-core counts.
    public func topology() -> CoreTopology {
        let total = ProcessInfo.processInfo.processorCount
        let performanceCount = Self.integerSysctl("hw.perflevel0.logicalcpu") ?? 0
        let efficiencyCount = Self.integerSysctl("hw.perflevel1.logicalcpu") ?? 0
        guard performanceCount + efficiencyCount == total, efficiencyCount > 0 else {
            return CoreTopology(
                coreKinds: Array(repeating: .unknown, count: total),
                performanceCoreCount: performanceCount,
                efficiencyCoreCount: efficiencyCount
            )
        }

        let coreKinds = (0..<total).map { index in
            index < efficiencyCount ? CPUCoreKind.efficiency : CPUCoreKind.performance
        }
        return CoreTopology(
            coreKinds: coreKinds,
            performanceCoreCount: performanceCount,
            efficiencyCoreCount: efficiencyCount
        )
    }

    /// Reads the 1-, 5-, and 15-minute load averages.
    public func loadAverages() -> [Double] {
        var values = [Double](repeating: 0, count: 3)
        let count = values.withUnsafeMutableBufferPointer { buffer in
            getloadavg(buffer.baseAddress, Int32(buffer.count))
        }
        guard count > 0 else {
            return []
        }
        return Array(values.prefix(Int(count)))
    }

    /// Reads elapsed time since boot.
    public func uptime() -> TimeInterval? {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &bootTime, &size, nil, 0) == 0 else {
            return nil
        }
        let boot = TimeInterval(bootTime.tv_sec) + TimeInterval(bootTime.tv_usec) / 1_000_000
        return max(0, Date().timeIntervalSince1970 - boot)
    }

    private static func integerSysctl(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else {
            return nil
        }
        return Int(value)
    }
}

/// Errors emitted by the Mach CPU source.
public enum CPUSourceError: Error, Sendable {
    case machError(kern_return_t)
}
