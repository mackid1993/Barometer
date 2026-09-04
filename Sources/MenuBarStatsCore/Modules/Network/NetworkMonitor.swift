import Foundation
import OSLog
import SystemSources

/// One interface's current addresses, cumulative totals, and transfer rates.
public struct NetworkInterfaceSample: Equatable, Sendable {
    public let name: String
    public let isUp: Bool
    public let isLoopback: Bool
    public let isVPN: Bool
    public let ipv4Addresses: [String]
    public let ipv6Addresses: [String]
    public let downloadBytesPerSecond: Double
    public let uploadBytesPerSecond: Double
    public let receivedBytes: UInt64
    public let sentBytes: UInt64
    public let inputErrors: UInt64
    public let outputErrors: UInt64

    /// Creates one interface sample.
    public init(
        name: String,
        isUp: Bool,
        isLoopback: Bool,
        isVPN: Bool,
        ipv4Addresses: [String],
        ipv6Addresses: [String],
        downloadBytesPerSecond: Double,
        uploadBytesPerSecond: Double,
        receivedBytes: UInt64,
        sentBytes: UInt64,
        inputErrors: UInt64,
        outputErrors: UInt64
    ) {
        self.name = name
        self.isUp = isUp
        self.isLoopback = isLoopback
        self.isVPN = isVPN
        self.ipv4Addresses = ipv4Addresses
        self.ipv6Addresses = ipv6Addresses
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
        self.receivedBytes = receivedBytes
        self.sentBytes = sentBytes
        self.inputErrors = inputErrors
        self.outputErrors = outputErrors
    }
}

/// Recent external-network activity attributed to one process.
public struct NetworkProcessSample: Equatable, Sendable {
    public let processIdentifier: pid_t
    public let name: String
    public let path: String?
    public let downloadBytesPerSecond: Double
    public let uploadBytesPerSecond: Double

    /// Creates one per-process network-rate sample.
    public init(
        processIdentifier: pid_t,
        name: String,
        path: String?,
        downloadBytesPerSecond: Double,
        uploadBytesPerSecond: Double
    ) {
        self.processIdentifier = processIdentifier
        self.name = name
        self.path = path
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
    }
}

/// A complete network sample with primary route and optional Wi-Fi detail.
public struct NetworkSample: Equatable, Sendable {
    public let timestamp: Date
    public let interfaces: [NetworkInterfaceSample]
    public let primaryInterface: String?
    public let router: String?
    public let dnsServers: [String]
    public let wifi: WiFiSnapshot?
    public let publicIP: PublicIPSnapshot?
    public let isProcessActivityAvailable: Bool
    public let topProcesses: [NetworkProcessSample]

    /// Creates a complete Network sample.
    public init(
        timestamp: Date,
        interfaces: [NetworkInterfaceSample],
        primaryInterface: String?,
        router: String?,
        dnsServers: [String],
        wifi: WiFiSnapshot?,
        publicIP: PublicIPSnapshot?,
        isProcessActivityAvailable: Bool = false,
        topProcesses: [NetworkProcessSample] = []
    ) {
        self.timestamp = timestamp
        self.interfaces = interfaces
        self.primaryInterface = primaryInterface
        self.router = router
        self.dnsServers = dnsServers
        self.wifi = wifi
        self.publicIP = publicIP
        self.isProcessActivityAvailable = isProcessActivityAvailable
        self.topProcesses = topProcesses
    }

    /// The primary interface sample when it is present.
    public var primary: NetworkInterfaceSample? {
        interfaces.first { $0.name == primaryInterface }
            ?? interfaces.first { $0.isUp && !$0.isLoopback }
    }

    /// Resolves a selected interface, falling back to the primary route.
    public func interface(named selectedName: String?) -> NetworkInterfaceSample? {
        selectedName.flatMap { name in interfaces.first { $0.name == name } } ?? primary
    }
}

/// Converts cumulative route counters into per-second network rates.
public actor NetworkMonitor: Monitor {
    public nonisolated let interval: Duration

    private let networkSource: NetworkSource
    private let wiFiSource: WiFiSource
    private let publicIPSource: PublicIPSource
    private let processNetworkSource: ProcessNetworkSource
    private let processSource: ProcessSource
    private var previousCounters: [String: PreviousCounter] = [:]
    private var previousProcessCounters: [pid_t: ProcessNetworkCounter] = [:]
    private var lastProcessRefresh: Date?
    private var isProcessActivityAvailable = false
    private var cachedTopProcesses: [NetworkProcessSample] = []
    private var isPublicIPEnabled = false
    private var publicIP: PublicIPSnapshot?
    private var lastPublicIPAttempt: Date?
    private var lastWiFiRefresh: Date?
    private var cachedWiFi: WiFiSnapshot?
    private var lastMetadataRefresh: Date?
    private var cachedMetadata: ConnectionMetadata?

    /// Slow-changing parts of a system snapshot, reused between metadata refreshes.
    private struct ConnectionMetadata {
        let addresses: [String: (ipv4: [String], ipv6: [String])]
        let primaryInterface: String?
        let router: String?
        let dnsServers: [String]

        init(snapshot: SystemNetworkSnapshot) {
            var addresses: [String: (ipv4: [String], ipv6: [String])] = [:]
            for interface in snapshot.interfaces {
                addresses[interface.name] = (interface.ipv4Addresses, interface.ipv6Addresses)
            }
            self.addresses = addresses
            primaryInterface = snapshot.primaryInterface
            router = snapshot.router
            dnsServers = snapshot.dnsServers
        }

        func applied(to snapshot: SystemNetworkSnapshot) -> SystemNetworkSnapshot {
            SystemNetworkSnapshot(
                interfaces: snapshot.interfaces.map { interface in
                    let cached = addresses[interface.name]
                    return NetworkInterfaceSnapshot(
                        name: interface.name,
                        index: interface.index,
                        isUp: interface.isUp,
                        isLoopback: interface.isLoopback,
                        isPointToPoint: interface.isPointToPoint,
                        ipv4Addresses: cached?.ipv4 ?? interface.ipv4Addresses,
                        ipv6Addresses: cached?.ipv6 ?? interface.ipv6Addresses,
                        receivedBytes: interface.receivedBytes,
                        sentBytes: interface.sentBytes,
                        receivedPackets: interface.receivedPackets,
                        sentPackets: interface.sentPackets,
                        inputErrors: interface.inputErrors,
                        outputErrors: interface.outputErrors
                    )
                },
                primaryInterface: primaryInterface,
                router: router,
                dnsServers: dnsServers
            )
        }
    }

    static func shouldRefreshMetadata(lastRefresh: Date?, now: Date) -> Bool {
        guard let lastRefresh else {
            return true
        }
        return now.timeIntervalSince(lastRefresh) >= metadataRefreshInterval
    }
    private static let logger = Logger(subsystem: "com.barometer.app", category: "network")

    /// Whether route counters are available.
    public var isAvailable: Bool {
        networkSource.isAvailable
    }

    /// Creates a Network monitor.
    public init(
        interval: Duration = .seconds(1),
        networkSource: NetworkSource = NetworkSource(),
        wiFiSource: WiFiSource = WiFiSource(),
        publicIPSource: PublicIPSource = PublicIPSource(),
        processNetworkSource: ProcessNetworkSource = ProcessNetworkSource()
    ) {
        self.interval = interval
        self.networkSource = networkSource
        self.wiFiSource = wiFiSource
        self.publicIPSource = publicIPSource
        self.processNetworkSource = processNetworkSource
        processSource = ProcessSource()
    }

    /// Enables or disables the explicit external public-address lookup.
    public func setPublicIPEnabled(_ isEnabled: Bool) {
        guard isPublicIPEnabled != isEnabled else {
            return
        }
        isPublicIPEnabled = isEnabled
        lastPublicIPAttempt = nil
        if !isEnabled {
            publicIP = nil
        }
    }

    /// Makes the next sample refresh the public address when it is enabled.
    public func refreshPublicIP() {
        lastPublicIPAttempt = nil
    }

    /// Invalidates cached connection metadata after the system network configuration changes.
    public func refreshConnectionDetails() {
        lastWiFiRefresh = nil
        lastMetadataRefresh = nil
    }

    /// Addresses and global configuration change rarely, so they are refreshed on this
    /// cadence (and immediately after a configuration change) instead of every sample.
    static let metadataRefreshInterval: TimeInterval = 10

    /// Reads interfaces and calculates transfer rates since the previous sample.
    public func sample() async throws -> NetworkSample {
        let timestamp = Date()
        let refreshesMetadata = Self.shouldRefreshMetadata(lastRefresh: lastMetadataRefresh, now: timestamp)
        var snapshot = try networkSource.read(includesMetadata: refreshesMetadata)
        if refreshesMetadata {
            lastMetadataRefresh = timestamp
            cachedMetadata = ConnectionMetadata(snapshot: snapshot)
        } else if let cachedMetadata {
            snapshot = cachedMetadata.applied(to: snapshot)
        }
        var nextCounters: [String: PreviousCounter] = [:]
        let interfaces = snapshot.interfaces.map { interface in
            let previous = previousCounters[interface.name]
            let elapsed = previous.map { timestamp.timeIntervalSince($0.timestamp) } ?? 0
            let receivedDelta =
                previous.map {
                    Self.counterDelta(from: $0.receivedBytes, to: interface.receivedBytes)
                } ?? 0
            let sentDelta =
                previous.map {
                    Self.counterDelta(from: $0.sentBytes, to: interface.sentBytes)
                } ?? 0
            nextCounters[interface.name] = PreviousCounter(
                timestamp: timestamp,
                receivedBytes: interface.receivedBytes,
                sentBytes: interface.sentBytes
            )
            return NetworkInterfaceSample(
                name: interface.name,
                isUp: interface.isUp,
                isLoopback: interface.isLoopback,
                isVPN: interface.name.hasPrefix("utun"),
                ipv4Addresses: interface.ipv4Addresses,
                ipv6Addresses: interface.ipv6Addresses,
                downloadBytesPerSecond: elapsed > 0 ? Double(receivedDelta) / elapsed : 0,
                uploadBytesPerSecond: elapsed > 0 ? Double(sentDelta) / elapsed : 0,
                receivedBytes: interface.receivedBytes,
                sentBytes: interface.sentBytes,
                inputErrors: interface.inputErrors,
                outputErrors: interface.outputErrors
            )
        }
        previousCounters = nextCounters
        refreshProcessActivityIfNeeded(at: timestamp)
        await updatePublicIPIfNeeded(at: timestamp)
        if Self.shouldRefreshWiFi(lastRefresh: lastWiFiRefresh, now: timestamp) {
            lastWiFiRefresh = timestamp
            cachedWiFi = wiFiSource.read(interfaceName: snapshot.primaryInterface)
        }
        return NetworkSample(
            timestamp: timestamp,
            interfaces: interfaces,
            primaryInterface: snapshot.primaryInterface,
            router: snapshot.router,
            dnsServers: snapshot.dnsServers,
            wifi: cachedWiFi,
            publicIP: publicIP,
            isProcessActivityAvailable: isProcessActivityAvailable,
            topProcesses: cachedTopProcesses
        )
    }

    static func shouldRefreshWiFi(
        lastRefresh: Date?,
        now: Date,
        interval: TimeInterval = 10
    ) -> Bool {
        lastRefresh.map { now.timeIntervalSince($0) >= interval } ?? true
    }

    static func counterDelta(from previous: UInt64, to current: UInt64) -> UInt64 {
        current >= previous ? current - previous : 0
    }

    private func updatePublicIPIfNeeded(at date: Date) async {
        guard isPublicIPEnabled else {
            return
        }
        if let lastPublicIPAttempt, date.timeIntervalSince(lastPublicIPAttempt) < 900 {
            return
        }
        lastPublicIPAttempt = date
        do {
            publicIP = try await publicIPSource.read()
        } catch {
            Self.logger.error("Public IP refresh failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func refreshProcessActivityIfNeeded(at timestamp: Date) {
        if let lastProcessRefresh, timestamp.timeIntervalSince(lastProcessRefresh) < 10 {
            return
        }
        let elapsed = lastProcessRefresh.map { timestamp.timeIntervalSince($0) } ?? 0
        lastProcessRefresh = timestamp
        do {
            let counters = try processNetworkSource.read()
            isProcessActivityAvailable = true
            let current = Dictionary(uniqueKeysWithValues: counters.map { ($0.processIdentifier, $0) })
            defer { previousProcessCounters = current }
            guard elapsed > 0 else {
                return
            }
            cachedTopProcesses = counters.compactMap { counter in
                guard let previous = previousProcessCounters[counter.processIdentifier],
                    previous.fallbackName == counter.fallbackName
                else {
                    return nil
                }
                let received = Self.counterDelta(from: previous.receivedBytes, to: counter.receivedBytes)
                let sent = Self.counterDelta(from: previous.sentBytes, to: counter.sentBytes)
                guard received > 0 || sent > 0 else {
                    return nil
                }
                let identity = processSource.identity(
                    processIdentifier: counter.processIdentifier,
                    fallbackName: counter.fallbackName
                )
                return NetworkProcessSample(
                    processIdentifier: counter.processIdentifier,
                    name: identity.name,
                    path: identity.path,
                    downloadBytesPerSecond: Double(received) / elapsed,
                    uploadBytesPerSecond: Double(sent) / elapsed
                )
            }
            .sorted {
                $0.downloadBytesPerSecond + $0.uploadBytesPerSecond
                    > $1.downloadBytesPerSecond + $1.uploadBytesPerSecond
            }
            .prefix(10)
            .map { $0 }
        } catch {
            isProcessActivityAvailable = false
            cachedTopProcesses = []
            Self.logger.error("Per-process network refresh failed: \(String(describing: error), privacy: .public)")
        }
    }
}

private struct PreviousCounter {
    let timestamp: Date
    let receivedBytes: UInt64
    let sentBytes: UInt64
}
