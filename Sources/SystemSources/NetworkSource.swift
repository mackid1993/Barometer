import Darwin
import Foundation
import SystemConfiguration

/// Cumulative counters and addresses for one network interface.
public struct NetworkInterfaceSnapshot: Equatable, Sendable {
    public let name: String
    public let index: UInt32
    public let isUp: Bool
    public let isLoopback: Bool
    public let isPointToPoint: Bool
    public let ipv4Addresses: [String]
    public let ipv6Addresses: [String]
    public let receivedBytes: UInt64
    public let sentBytes: UInt64
    public let receivedPackets: UInt64
    public let sentPackets: UInt64
    public let inputErrors: UInt64
    public let outputErrors: UInt64
}

/// One system-wide network configuration and counter snapshot.
public struct SystemNetworkSnapshot: Equatable, Sendable {
    public let interfaces: [NetworkInterfaceSnapshot]
    public let primaryInterface: String?
    public let router: String?
    public let dnsServers: [String]
}

/// Failures surfaced while reading the routing information base.
public enum NetworkSourceError: Error, Sendable {
    case sysctl(Int32)
}

/// Reads interface counters from `NET_RT_IFLIST2` and configuration from SystemConfiguration.
public struct NetworkSource: Sendable {
    /// Whether the routing information base exposes at least one interface.
    public var isAvailable: Bool {
        (try? read()).map { !$0.interfaces.isEmpty } ?? false
    }

    /// Creates a network source.
    public init() {}

    /// Reads cumulative interface counters, addresses, and primary network configuration.
    public func read() throws -> SystemNetworkSnapshot {
        let counters = try routeCounters()
        let addresses = Self.interfaceAddresses()
        let interfaces = counters.values.map { counter in
            let interfaceAddresses = addresses[counter.name] ?? InterfaceAddresses()
            return NetworkInterfaceSnapshot(
                name: counter.name,
                index: counter.index,
                isUp: counter.flags & UInt32(IFF_UP) != 0,
                isLoopback: counter.flags & UInt32(IFF_LOOPBACK) != 0,
                isPointToPoint: counter.flags & UInt32(IFF_POINTOPOINT) != 0,
                ipv4Addresses: interfaceAddresses.ipv4.sorted(),
                ipv6Addresses: interfaceAddresses.ipv6.sorted(),
                receivedBytes: counter.receivedBytes,
                sentBytes: counter.sentBytes,
                receivedPackets: counter.receivedPackets,
                sentPackets: counter.sentPackets,
                inputErrors: counter.inputErrors,
                outputErrors: counter.outputErrors
            )
        }
        .sorted { $0.index < $1.index }
        let globalIPv4 = Self.dynamicStoreDictionary(key: "State:/Network/Global/IPv4")
        let globalDNS = Self.dynamicStoreDictionary(key: "State:/Network/Global/DNS")
        return SystemNetworkSnapshot(
            interfaces: interfaces,
            primaryInterface: globalIPv4?["PrimaryInterface"] as? String,
            router: globalIPv4?["Router"] as? String,
            dnsServers: globalDNS?["ServerAddresses"] as? [String] ?? []
        )
    }

    private func routeCounters() throws -> [UInt32: InterfaceCounters] {
        var managementInformationBase: [Int32] = [
            CTL_NET,
            PF_ROUTE,
            0,
            0,
            NET_RT_IFLIST2,
            0,
        ]
        var byteCount = 0
        guard sysctl(&managementInformationBase, 6, nil, &byteCount, nil, 0) == 0 else {
            throw NetworkSourceError.sysctl(errno)
        }
        var bytes = [UInt8](repeating: 0, count: byteCount)
        guard sysctl(&managementInformationBase, 6, &bytes, &byteCount, nil, 0) == 0 else {
            throw NetworkSourceError.sysctl(errno)
        }

        var result: [UInt32: InterfaceCounters] = [:]
        bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= byteCount {
                let header = buffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let messageLength = Int(header.ifm_msglen)
                guard messageLength > 0, offset + messageLength <= byteCount else {
                    break
                }
                if Int32(header.ifm_type) == RTM_IFINFO2,
                   messageLength >= MemoryLayout<if_msghdr2>.size {
                    let message = buffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    let index = UInt32(message.ifm_index)
                    if let name = Self.interfaceName(index: index) {
                        result[index] = InterfaceCounters(
                            name: name,
                            index: index,
                            flags: UInt32(bitPattern: message.ifm_flags),
                            receivedBytes: message.ifm_data.ifi_ibytes,
                            sentBytes: message.ifm_data.ifi_obytes,
                            receivedPackets: message.ifm_data.ifi_ipackets,
                            sentPackets: message.ifm_data.ifi_opackets,
                            inputErrors: message.ifm_data.ifi_ierrors,
                            outputErrors: message.ifm_data.ifi_oerrors
                        )
                    }
                }
                offset += messageLength
            }
        }
        return result
    }

    private static func interfaceName(index: UInt32) -> String? {
        var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        guard if_indextoname(index, &name) != nil else {
            return nil
        }
        return Self.string(fromNullTerminated: name)
    }

    private static func interfaceAddresses() -> [String: InterfaceAddresses] {
        var firstAddress: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&firstAddress) == 0, let firstAddress else {
            return [:]
        }
        defer { freeifaddrs(firstAddress) }

        var result: [String: InterfaceAddresses] = [:]
        var current: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while let pointer = current {
            let interface = pointer.pointee
            if let address = interface.ifa_addr {
                let family = Int32(address.pointee.sa_family)
                if family == AF_INET || family == AF_INET6,
                   let string = numericAddress(address) {
                    let name = String(cString: interface.ifa_name)
                    var values = result[name] ?? InterfaceAddresses()
                    if family == AF_INET {
                        values.ipv4.append(string)
                    } else {
                        values.ipv6.append(string)
                    }
                    result[name] = values
                }
            }
            current = interface.ifa_next
        }
        return result
    }

    private static func numericAddress(_ address: UnsafePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(
            address,
            socklen_t(address.pointee.sa_len),
            &host,
            socklen_t(host.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        return result == 0 ? Self.string(fromNullTerminated: host) : nil
    }

    private static func dynamicStoreDictionary(key: String) -> [String: Any]? {
        SCDynamicStoreCopyValue(nil, key as CFString) as? [String: Any]
    }

    private static func string(fromNullTerminated characters: [CChar]) -> String {
        let bytes = characters.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}

private struct InterfaceCounters {
    let name: String
    let index: UInt32
    let flags: UInt32
    let receivedBytes: UInt64
    let sentBytes: UInt64
    let receivedPackets: UInt64
    let sentPackets: UInt64
    let inputErrors: UInt64
    let outputErrors: UInt64
}

private struct InterfaceAddresses {
    var ipv4: [String] = []
    var ipv6: [String] = []
}
