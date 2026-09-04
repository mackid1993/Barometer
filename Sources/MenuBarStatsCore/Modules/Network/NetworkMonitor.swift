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

/// A complete network sample with primary route and optional Wi-Fi detail.
public struct NetworkSample: Equatable, Sendable {
    public let timestamp: Date
    public let interfaces: [NetworkInterfaceSample]
    public let primaryInterface: String?
    public let router: String?
    public let dnsServers: [String]
    public let wifi: WiFiSnapshot?
    public let publicIP: PublicIPSnapshot?

    /// Creates a complete Network sample.
    public init(
        timestamp: Date,
        interfaces: [NetworkInterfaceSample],
        primaryInterface: String?,
        router: String?,
        dnsServers: [String],
        wifi: WiFiSnapshot?,
        publicIP: PublicIPSnapshot?
    ) {
        self.timestamp = timestamp
        self.interfaces = interfaces
        self.primaryInterface = primaryInterface
        self.router = router
        self.dnsServers = dnsServers
        self.wifi = wifi
        self.publicIP = publicIP
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
    private var previousCounters: [String: PreviousCounter] = [:]
    private var isPublicIPEnabled = false
    private var publicIP: PublicIPSnapshot?
    private var lastPublicIPAttempt: Date?
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
        publicIPSource: PublicIPSource = PublicIPSource()
    ) {
        self.interval = interval
        self.networkSource = networkSource
        self.wiFiSource = wiFiSource
        self.publicIPSource = publicIPSource
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

    /// Reads interfaces and calculates transfer rates since the previous sample.
    public func sample() async throws -> NetworkSample {
        let timestamp = Date()
        let snapshot = try networkSource.read()
        var nextCounters: [String: PreviousCounter] = [:]
        let interfaces = snapshot.interfaces.map { interface in
            let previous = previousCounters[interface.name]
            let elapsed = previous.map { timestamp.timeIntervalSince($0.timestamp) } ?? 0
            let receivedDelta = previous.map {
                Self.counterDelta(from: $0.receivedBytes, to: interface.receivedBytes)
            } ?? 0
            let sentDelta = previous.map {
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
        await updatePublicIPIfNeeded(at: timestamp)
        return NetworkSample(
            timestamp: timestamp,
            interfaces: interfaces,
            primaryInterface: snapshot.primaryInterface,
            router: snapshot.router,
            dnsServers: snapshot.dnsServers,
            wifi: wiFiSource.read(interfaceName: snapshot.primaryInterface),
            publicIP: publicIP
        )
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
}

private struct PreviousCounter {
    let timestamp: Date
    let receivedBytes: UInt64
    let sentBytes: UInt64
}
