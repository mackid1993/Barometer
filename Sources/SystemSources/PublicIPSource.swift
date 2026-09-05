import Darwin
import Foundation

/// Public addresses returned by the opt-in external address lookup.
public struct PublicIPSnapshot: Equatable, Sendable {
    public let ipv4: String?
    public let ipv6: String?

    /// Creates a public address snapshot.
    public init(ipv4: String?, ipv6: String?) {
        self.ipv4 = ipv4
        self.ipv6 = ipv6
    }
}

/// Failures surfaced while resolving an opted-in public address.
public enum PublicIPSourceError: Error, Sendable {
    case invalidResponse
    case unavailable
}

/// Reads public IPv4 and IPv6 addresses from ipify when explicitly requested.
///
/// This source never runs automatically. The Network module owns the opt-in and
/// the 15-minute cache policy described by the design.
public struct PublicIPSource: Sendable {
    private let session: URLSession

    /// Creates a public address source.
    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Resolves both address families independently, preserving either successful result.
    public func read() async throws -> PublicIPSnapshot {
        async let ipv4 = try? readAddress(from: "https://api.ipify.org?format=json", family: AF_INET)
        async let ipv6 = try? readAddress(from: "https://api64.ipify.org?format=json", family: AF_INET6)
        let snapshot = await PublicIPSnapshot(ipv4: ipv4, ipv6: ipv6)
        guard snapshot.ipv4 != nil || snapshot.ipv6 != nil else {
            throw PublicIPSourceError.unavailable
        }
        return snapshot
    }

    private func readAddress(from endpoint: String, family: Int32) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw PublicIPSourceError.invalidResponse
        }
        let (data, response) = try await session.data(from: url)
        guard let response = response as? HTTPURLResponse,
            (200..<300).contains(response.statusCode),
            let address = Self.address(from: data),
            Self.isValid(address: address, family: family)
        else {
            throw PublicIPSourceError.invalidResponse
        }
        return address
    }

    static func address(from data: Data) -> String? {
        struct Response: Decodable {
            let ip: String
        }
        return try? JSONDecoder().decode(Response.self, from: data).ip
    }

    static func isValid(address: String, family: Int32) -> Bool {
        var storage = in6_addr()
        return address.withCString { inet_pton(family, $0, &storage) == 1 }
    }
}
