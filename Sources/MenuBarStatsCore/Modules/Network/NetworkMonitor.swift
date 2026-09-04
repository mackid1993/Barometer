import Foundation
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
}

/// A complete network sample with primary route and optional Wi-Fi detail.
public struct NetworkSample: Equatable, Sendable {
    public let timestamp: Date
    public let interfaces: [NetworkInterfaceSample]
    public let primaryInterface: String?
    public let router: String?
    public let dnsServers: [String]
    public let wifi: WiFiSnapshot?

    /// The primary interface sample when it is present.
    public var primary: NetworkInterfaceSample? {
        interfaces.first { $0.name == primaryInterface }
            ?? interfaces.first { $0.isUp && !$0.isLoopback }
    }
}

/// Converts cumulative route counters into per-second network rates.
public actor NetworkMonitor: Monitor {
    public nonisolated let interval: Duration

    private let networkSource: NetworkSource
    private let wiFiSource: WiFiSource
    private var previousCounters: [String: PreviousCounter] = [:]

    /// Whether route counters are available.
    public var isAvailable: Bool {
        networkSource.isAvailable
    }

    /// Creates a Network monitor.
    public init(interval: Duration = .seconds(1)) {
        self.interval = interval
        networkSource = NetworkSource()
        wiFiSource = WiFiSource()
    }

    /// Reads interfaces and calculates transfer rates since the previous sample.
    public func sample() throws -> NetworkSample {
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
        return NetworkSample(
            timestamp: timestamp,
            interfaces: interfaces,
            primaryInterface: snapshot.primaryInterface,
            router: snapshot.router,
            dnsServers: snapshot.dnsServers,
            wifi: wiFiSource.read(interfaceName: snapshot.primaryInterface)
        )
    }

    private static func counterDelta(from previous: UInt64, to current: UInt64) -> UInt64 {
        current >= previous ? current - previous : 0
    }
}

private struct PreviousCounter {
    let timestamp: Date
    let receivedBytes: UInt64
    let sentBytes: UInt64
}
