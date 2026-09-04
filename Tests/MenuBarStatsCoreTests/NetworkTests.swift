import Foundation
@testable import MenuBarStatsCore
import Testing

@Suite("NetworkTests")
struct NetworkTests {
    @Test("network rates use decimal byte and bit units")
    func formatsRates() {
        #expect(NetworkRateFormatter.string(bytesPerSecond: 1_250_000, unit: .bytes) == "1.2 MB/s")
        #expect(NetworkRateFormatter.string(bytesPerSecond: 1_000_000, unit: .bits) == "8.0 Mb/s")
        #expect(NetworkRateFormatter.compactString(bytesPerSecond: 82_000, unit: .bytes) == "82.0KB")
        #expect(NetworkRateFormatter.string(bytesPerSecond: -1, unit: .bytes) == "0.0 B/s")
        #expect(
            NetworkRateFormatter.compactString(bytesPerSecond: 82_000, unit: .bytes, decimalPlaces: 0) == "82KB"
        )
        #expect(
            NetworkRateFormatter.compactString(bytesPerSecond: 82_000, unit: .bytes, decimalPlaces: 2) == "82.00KB"
        )
        #expect(NetworkRateFormatter.compactPlaceholder(unit: .bytes, decimalPlaces: 2) == "999.99GB")
    }

    @Test("network decimal precision migrates without losing prior preferences")
    func migratesDecimalPrecision() throws {
        let encoded = try JSONEncoder().encode(NetworkSettings(rateUnit: .bits, showsPublicIP: true))
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "decimalPlaces")
        let oldData = try JSONSerialization.data(withJSONObject: object)

        let migrated = try JSONDecoder().decode(NetworkSettings.self, from: oldData)

        #expect(migrated.decimalPlaces == 1)
        #expect(migrated.rateUnit == .bits)
        #expect(migrated.showsPublicIP)
    }

    @Test("selected interfaces fall back to the primary route")
    func selectsInterface() throws {
        let ethernet = interface(name: "en0", download: 10)
        let vpn = interface(name: "utun3", download: 20)
        let sample = NetworkSample(
            timestamp: Date(timeIntervalSince1970: 0),
            interfaces: [ethernet, vpn],
            primaryInterface: "en0",
            router: nil,
            dnsServers: [],
            wifi: nil,
            publicIP: nil
        )

        #expect(sample.interface(named: "utun3") == vpn)
        #expect(sample.interface(named: "missing") == ethernet)
        #expect(sample.interface(named: nil) == ethernet)
    }

    @Test("counter resets never become impossible transfer spikes")
    func handlesCounterReset() {
        #expect(NetworkMonitor.counterDelta(from: 100, to: 140) == 40)
        #expect(NetworkMonitor.counterDelta(from: 140, to: 5) == 0)
    }

    private func interface(name: String, download: Double) -> NetworkInterfaceSample {
        NetworkInterfaceSample(
            name: name,
            isUp: true,
            isLoopback: false,
            isVPN: name.hasPrefix("utun"),
            ipv4Addresses: [],
            ipv6Addresses: [],
            downloadBytesPerSecond: download,
            uploadBytesPerSecond: 0,
            receivedBytes: 0,
            sentBytes: 0,
            inputErrors: 0,
            outputErrors: 0
        )
    }
}
