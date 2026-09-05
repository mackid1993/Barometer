import Foundation
@testable import MenuBarStatsCore
import Testing

@Suite("NetworkTests")
struct NetworkTests {
    @Test("network rates use decimal byte and bit units")
    func formatsRates() {
        #expect(NetworkRateFormatter.string(bytesPerSecond: 1_250_000, unit: .bytes) == "1.2 MB/s")
        #expect(NetworkRateFormatter.string(bytesPerSecond: 1_000_000, unit: .bits) == "8.0 Mb/s")
        #expect(NetworkRateFormatter.compactString(bytesPerSecond: 82_000, unit: .bytes) == "82.0KB/s")
        #expect(NetworkRateFormatter.string(bytesPerSecond: 62, unit: .bytes, decimalPlaces: 2) == "0.06 KB/s")
        #expect(NetworkRateFormatter.compactString(bytesPerSecond: 62, unit: .bytes, decimalPlaces: 2) == "0.06KB/s")
        #expect(NetworkRateFormatter.string(bytesPerSecond: -1, unit: .bytes) == "0.0 KB/s")
        #expect(
            NetworkRateFormatter.compactString(bytesPerSecond: 99_994, unit: .bytes, decimalPlaces: 2) == "99.99KB/s"
        )
        #expect(
            NetworkRateFormatter.compactString(bytesPerSecond: 99_995, unit: .bytes, decimalPlaces: 2) == "0.10MB/s"
        )
        #expect(
            NetworkRateFormatter.compactString(bytesPerSecond: 125_000, unit: .bytes, decimalPlaces: 2) == "0.12MB/s"
        )
        #expect(NetworkRateFormatter.string(bytesPerSecond: 125_000, unit: .bytes, decimalPlaces: 2) == "125.00 KB/s")
        #expect(
            NetworkRateFormatter.compactString(bytesPerSecond: 82_000, unit: .bytes, decimalPlaces: 0) == "82KB/s"
        )
        #expect(
            NetworkRateFormatter.compactString(bytesPerSecond: 82_000, unit: .bytes, decimalPlaces: 2) == "82.00KB/s"
        )
        #expect(NetworkRateFormatter.compactPlaceholder(unit: .bytes, decimalPlaces: 2) == "99.99MB/s")
        #expect(NetworkRateFormatter.compactString(bytesPerSecond: 1_250_000, unit: .bits) == "10.0Mb/s")
    }

    @Test("network decimal precision migrates without losing prior preferences")
    func migratesDecimalPrecision() throws {
        let encoded = try JSONEncoder().encode(NetworkSettings(rateUnit: .bits, showsPublicIP: true))
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "decimalPlaces")
        object.removeValue(forKey: "rateOrder")
        let oldData = try JSONSerialization.data(withJSONObject: object)

        let migrated = try JSONDecoder().decode(NetworkSettings.self, from: oldData)

        #expect(migrated.decimalPlaces == 1)
        #expect(migrated.rateOrder == .uploadThenDownload)
        #expect(migrated.rateUnit == .bits)
        #expect(migrated.showsPublicIP)
    }

    @Test("network metadata refresh is throttled without delaying transfer rates")
    func throttlesConnectionMetadata() {
        let start = Date(timeIntervalSince1970: 100)

        #expect(NetworkMonitor.shouldRefreshMetadata(
            hasCachedMetadata: false,
            collectsConnectionDetails: false,
            lastRefresh: nil,
            now: start
        ))
        #expect(!NetworkMonitor.shouldRefreshMetadata(
            hasCachedMetadata: true,
            collectsConnectionDetails: false,
            lastRefresh: start,
            now: start.addingTimeInterval(60)
        ))
        #expect(NetworkMonitor.shouldRefreshMetadata(
            hasCachedMetadata: true,
            collectsConnectionDetails: true,
            lastRefresh: start,
            now: start.addingTimeInterval(10)
        ))
        #expect(NetworkMonitor.shouldRefreshWiFi(lastRefresh: nil, now: start))
        #expect(!NetworkMonitor.shouldRefreshWiFi(lastRefresh: start, now: start.addingTimeInterval(9.9)))
        #expect(NetworkMonitor.shouldRefreshWiFi(lastRefresh: start, now: start.addingTimeInterval(10)))
        #expect(NetworkSettings().rateOrder == .uploadThenDownload)
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
        #expect(sample.graphValue.interface(named: "utun3")?.downloadBytesPerSecond == 20)
        #expect(sample.graphValue.interface(named: "missing")?.downloadBytesPerSecond == 10)
        #expect(sample.graphValue.interface(named: nil)?.name == "en0")
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
