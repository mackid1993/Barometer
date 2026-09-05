import Darwin
import Foundation
import Synchronization

/// One process observation derived from libproc.
public struct ProcessSnapshot: Sendable {
    /// Process identifier.
    public let processIdentifier: pid_t

    /// Cached process name.
    public let name: String

    /// Cached executable path when available.
    public let path: String?

    /// CPU use as a percentage of total machine capacity since the previous observation.
    public let cpuPercent: Double

    /// Physical memory footprint in bytes.
    public let physicalFootprint: UInt64

    /// Current thread count reported by libproc.
    public let threadCount: Int

    /// Effective user identifier owning the process.
    public let userIdentifier: uid_t
}

/// Aggregate process-list observation.
public struct ProcessListSnapshot: Sendable {
    /// Every process whose resource usage could be read.
    public let processes: [ProcessSnapshot]

    /// Number of process identifiers returned by libproc.
    public let processCount: Int

    /// Sum of readable per-process thread counts.
    public let threadCount: Int
}

/// Resolved display identity for a running process.
public struct ProcessIdentitySnapshot: Sendable {
    public let processIdentifier: pid_t
    public let name: String
    public let path: String?
}

/// Reads and caches process metadata and resource usage through libproc.
public final class ProcessSource {
    private struct CacheEntry {
        let startTime: UInt64
        let name: String
        let path: String?
        let cpuTime: UInt64
        let observedAt: ContinuousClock.Instant
        let threadCount: Int
        let userIdentifier: uid_t
    }

    private var cache: [pid_t: CacheEntry] = [:]
    private var lastDetailRefresh: ContinuousClock.Instant?
    private let timebaseScale: Double

    /// Whether libproc returns at least one process identifier.
    public var isAvailable: Bool {
        !processIdentifiers().isEmpty
    }

    /// Creates a process source with an empty metadata cache.
    public init() {
        var timebase = mach_timebase_info_data_t()
        if mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.denom != 0 {
            timebaseScale = Double(timebase.numer) / Double(timebase.denom)
        } else {
            timebaseScale = 1
        }
    }

    /// Reads processes, calculating CPU deltas against the previous call.
    public func readProcesses(logicalCPUCount: Int) -> ProcessListSnapshot {
        let processIdentifiers = processIdentifiers()
        let now = ContinuousClock().now
        let refreshDetails = lastDetailRefresh.map { $0.duration(to: now).timeInterval >= 15 } ?? true
        let divisor = Double(max(1, logicalCPUCount))
        var nextCache: [pid_t: CacheEntry] = [:]
        var snapshots: [ProcessSnapshot] = []
        var totalThreads = 0

        for processIdentifier in processIdentifiers {
            guard let usage = resourceUsage(for: processIdentifier) else {
                continue
            }
            let startTime = usage.ri_proc_start_abstime
            let cpuTime = usage.ri_user_time &+ usage.ri_system_time
            let cached = cache[processIdentifier]
            let metadataMatches = cached?.startTime == startTime
            let path = metadataMatches ? cached?.path : processPath(for: processIdentifier)
            let name: String
            if metadataMatches {
                name = cached?.name ?? ""
            } else {
                name =
                    path.flatMap(Self.applicationDisplayName(forExecutablePath:))
                    ?? processName(for: processIdentifier)
            }

            let cpuPercent: Double
            if let cached, cached.startTime == startTime, cpuTime >= cached.cpuTime {
                let wallSeconds = cached.observedAt.duration(to: now).timeInterval
                let cpuSeconds = Double(cpuTime - cached.cpuTime) * timebaseScale / 1_000_000_000
                cpuPercent = wallSeconds > 0 ? min(100, cpuSeconds / wallSeconds * 100 / divisor) : 0
            } else {
                cpuPercent = 0
            }

            let threadCount: Int
            let userIdentifier: uid_t
            if metadataMatches, !refreshDetails, let cached {
                threadCount = cached.threadCount
                userIdentifier = cached.userIdentifier
            } else {
                threadCount = processThreadCount(for: processIdentifier)
                userIdentifier = processUserIdentifier(for: processIdentifier)
            }
            totalThreads += threadCount
            snapshots.append(
                ProcessSnapshot(
                    processIdentifier: processIdentifier,
                    name: name.isEmpty ? "PID \(processIdentifier)" : name,
                    path: path,
                    cpuPercent: cpuPercent,
                    physicalFootprint: usage.ri_phys_footprint,
                    threadCount: threadCount,
                    userIdentifier: userIdentifier
                )
            )
            nextCache[processIdentifier] = CacheEntry(
                startTime: startTime,
                name: name,
                path: path,
                cpuTime: cpuTime,
                observedAt: now,
                threadCount: threadCount,
                userIdentifier: userIdentifier
            )
        }

        cache = nextCache
        if refreshDetails {
            lastDetailRefresh = now
        }
        return ProcessListSnapshot(
            processes: snapshots,
            processCount: processIdentifiers.count,
            threadCount: totalThreads
        )
    }

    /// Resolves a process to its containing application's name and executable path.
    public func identity(processIdentifier: pid_t, fallbackName: String) -> ProcessIdentitySnapshot {
        let path = processPath(for: processIdentifier)
        let processName = processName(for: processIdentifier)
        let name =
            path.flatMap(Self.applicationDisplayName(forExecutablePath:))
            ?? (processName.isEmpty ? nil : processName)
            ?? fallbackName
        return ProcessIdentitySnapshot(processIdentifier: processIdentifier, name: name, path: path)
    }

    private func processIdentifiers() -> [pid_t] {
        let requiredBytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard requiredBytes > 0 else {
            return []
        }

        let capacity = Int(requiredBytes) / MemoryLayout<pid_t>.stride + 32
        var values = [pid_t](repeating: 0, count: capacity)
        let actualBytes = values.withUnsafeMutableBytes { buffer in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, buffer.baseAddress, Int32(buffer.count))
        }
        guard actualBytes > 0 else {
            return []
        }
        return values.prefix(Int(actualBytes) / MemoryLayout<pid_t>.stride).filter { $0 > 0 }
    }

    private func resourceUsage(for processIdentifier: pid_t) -> rusage_info_v4? {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { usagePointer in
            let reboundPointer = UnsafeMutableRawPointer(usagePointer)
                .assumingMemoryBound(to: rusage_info_t?.self)
            return proc_pid_rusage(processIdentifier, RUSAGE_INFO_V4, reboundPointer)
        }
        return result == 0 ? usage : nil
    }

    private func processName(for processIdentifier: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 1_024)
        let result = proc_name(processIdentifier, &buffer, UInt32(buffer.count))
        guard result > 0 else {
            return ""
        }
        return Self.string(from: buffer, byteCount: Int(result))
    }

    private func processPath(for processIdentifier: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4_096)
        let result = proc_pidpath(processIdentifier, &buffer, UInt32(buffer.count))
        guard result > 0 else {
            return nil
        }
        return Self.string(from: buffer, byteCount: Int(result))
    }

    private func processThreadCount(for processIdentifier: pid_t) -> Int {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidinfo(processIdentifier, PROC_PIDTASKINFO, 0, pointer, size)
        }
        return result == size ? Int(info.pti_threadnum) : 0
    }

    private func processUserIdentifier(for processIdentifier: pid_t) -> uid_t {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidinfo(processIdentifier, PROC_PIDTBSDINFO, 0, pointer, size)
        }
        return result == size ? info.pbi_uid : uid_t.max
    }

    private static func string(from buffer: [CChar], byteCount: Int) -> String {
        let bytes = buffer.prefix(byteCount).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    static func applicationBundleURL(forExecutablePath path: String) -> URL? {
        var candidate = URL(fileURLWithPath: path).deletingLastPathComponent()
        while candidate.path != "/" {
            if candidate.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        return nil
    }

    /// Resolved display names are stable per executable path, and resolving one maps the
    /// application bundle's property lists. Every refresh cycle walks hundreds of processes,
    /// so the resolved value is cached to keep those mapped files from accumulating in
    /// long-running sessions. The empty string caches a path with no display name.
    ///
    /// A Mutex guards the dictionary because readProcesses runs on monitor tasks off the main actor.
    private static let displayNameCache = Mutex<[String: String]>([:])
    private static let displayNameCacheLimit = 512

    static func applicationDisplayName(forExecutablePath path: String) -> String? {
        let cached = displayNameCache.withLock { $0[path] }
        if let cached {
            return cached.isEmpty ? nil : cached
        }

        let resolved = resolveApplicationDisplayName(forExecutablePath: path)

        displayNameCache.withLock { cache in
            if cache.count >= displayNameCacheLimit, let oldest = cache.keys.first {
                cache.removeValue(forKey: oldest)
            }
            cache[path] = resolved ?? ""
        }
        return resolved
    }

    private static func resolveApplicationDisplayName(forExecutablePath path: String) -> String? {
        guard let applicationURL = applicationBundleURL(forExecutablePath: path),
            let bundle = Bundle(url: applicationURL)
        else {
            return nil
        }
        let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
        return [displayName, bundleName, applicationURL.deletingPathExtension().lastPathComponent]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

extension Duration {
    fileprivate var timeInterval: TimeInterval {
        let value = components
        return TimeInterval(value.seconds) + TimeInterval(value.attoseconds) / 1e18
    }
}
