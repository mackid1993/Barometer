import Darwin
import Dispatch
import Foundation

/// Current system memory-pressure severity.
public enum MemoryPressureLevel: String, Sendable {
    case normal
    case warning
    case critical
    case unavailable
}

/// Raw memory values derived from Mach and sysctl.
public struct SystemMemorySnapshot: Sendable {
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

    /// Pressure severity derived from the memorystatus level.
    public let pressureLevel: MemoryPressureLevel

    /// Swap currently in use, in bytes.
    public let swapUsed: UInt64

    /// Configured swap capacity, in bytes.
    public let swapTotal: UInt64
}

/// Reads virtual-memory statistics, pressure, and swap from Mach and sysctl.
public struct MemorySource: Sendable {
    /// Whether required physical-memory and VM statistics are readable.
    public var isAvailable: Bool {
        (try? read()).map { $0.total > 0 } ?? false
    }

    /// Creates a memory source.
    public init() {}

    /// Reads one complete memory snapshot.
    public func read() throws -> SystemMemorySnapshot {
        let total = try Self.totalMemory()
        let statistics = try Self.virtualMemoryStatistics()
        let pageSize = try Self.pageSize()

        let internalPages = UInt64(statistics.internal_page_count)
        let purgeablePages = UInt64(statistics.purgeable_count)
        let appPages = internalPages >= purgeablePages ? internalPages - purgeablePages : 0
        let wiredPages = UInt64(statistics.wire_count)
        let compressedPages = UInt64(statistics.compressor_page_count)
        let cachedPages = UInt64(statistics.external_page_count) + purgeablePages

        let app = appPages * pageSize
        let wired = wiredPages * pageSize
        let compressed = compressedPages * pageSize
        let cached = cachedPages * pageSize
        let used = min(total, app + wired + compressed)
        let free = total - used
        let pressurePercent = Self.pressurePercent()
        let swap = Self.swapUsage()

        return SystemMemorySnapshot(
            total: total,
            used: used,
            app: app,
            wired: wired,
            compressed: compressed,
            cached: cached,
            free: free,
            pressurePercent: pressurePercent,
            pressureLevel: Self.pressureLevel(for: pressurePercent),
            swapUsed: swap?.used ?? 0,
            swapTotal: swap?.total ?? 0
        )
    }

    private static func totalMemory() throws -> UInt64 {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname("hw.memsize", &value, &size, nil, 0) == 0 else {
            throw MemorySourceError.sysctlFailed("hw.memsize")
        }
        return value
    }

    private static func pageSize() throws -> UInt64 {
        var value: vm_size_t = 0
        let result = host_page_size(mach_host_self(), &value)
        guard result == KERN_SUCCESS else {
            throw MemorySourceError.machError(result)
        }
        return UInt64(value)
    }

    private static func virtualMemoryStatistics() throws -> vm_statistics64 {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            throw MemorySourceError.machError(result)
        }
        return statistics
    }

    private static func pressurePercent() -> Double {
        var freeLevel: Int32 = 100
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_level", &freeLevel, &size, nil, 0) == 0 else {
            return 0
        }
        return min(100, max(0, 100 - Double(freeLevel)))
    }

    private static func pressureLevel(for pressurePercent: Double) -> MemoryPressureLevel {
        switch pressurePercent {
        case 90...: .critical
        case 70...: .warning
        default: .normal
        }
    }

    private static func swapUsage() -> (used: UInt64, total: UInt64)? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else {
            return nil
        }
        return (usage.xsu_used, usage.xsu_total)
    }
}

/// Errors emitted by the system memory source.
public enum MemorySourceError: Error, Sendable {
    case machError(kern_return_t)
    case sysctlFailed(String)
}

/// Delivers kernel memory-pressure transitions on the main actor.
@MainActor
public final class MemoryPressureWatcher {
    /// Called when the kernel pressure state changes.
    public var onChange: (@MainActor (MemoryPressureLevel) -> Void)?

    private let source: DispatchSourceMemoryPressure

    /// Starts observing normal, warning, and critical memory-pressure events.
    public init() {
        source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.handleEvent()
            }
        }
        source.resume()
    }

    deinit {
        source.cancel()
    }

    private func handleEvent() {
        let event = source.data
        let level: MemoryPressureLevel
        if event.contains(.critical) {
            level = .critical
        } else if event.contains(.warning) {
            level = .warning
        } else {
            level = .normal
        }
        onChange?(level)
    }
}
