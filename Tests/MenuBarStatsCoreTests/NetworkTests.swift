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

    @Test("All interfaces sums every active device, including internal ones")
    @MainActor
    func aggregatesEveryActiveInterface() {
        func iface(_ name: String, up: Bool, loopback: Bool, down: Double, up_: Double) -> NetworkInterfaceSample {
            NetworkInterfaceSample(
                name: name, isUp: up, isLoopback: loopback, isVPN: false,
                ipv4Addresses: [], ipv6Addresses: [],
                downloadBytesPerSecond: down, uploadBytesPerSecond: up_,
                receivedBytes: 10, sentBytes: 20, inputErrors: 1, outputErrors: 2)
        }
        let sample = NetworkSample(
            timestamp: Date(),
            interfaces: [
                iface("en0", up: true, loopback: false, down: 100, up_: 200),
                iface("lo0", up: true, loopback: true, down: 5, up_: 7),
                iface("vmenet0", up: true, loopback: false, down: 3, up_: 11),
                iface("en4", up: false, loopback: false, down: 999, up_: 999),
            ],
            primaryInterface: "en0", router: nil, dnsServers: [], wifi: nil, publicIP: nil)

        let all = sample.interface(named: NetworkSample.allInterfacesName)
        // Loopback and virtual devices are internal activity and must be counted; a down interface
        // must not be.
        #expect(all?.downloadBytesPerSecond == 108)
        #expect(all?.uploadBytesPerSecond == 218)
        #expect(all?.receivedBytes == 30)
        #expect(all?.sentBytes == 60)

        // A named selection is that device alone.
        #expect(sample.interface(named: "en0")?.downloadBytesPerSecond == 100)
        #expect(sample.interface(named: "lo0")?.downloadBytesPerSecond == 5)

        // Automatic keeps the primary's identity but counts every local network: en0 plus the
        // virtual machine bridge, not loopback.
        let auto = sample.interface(named: nil)
        #expect(auto?.name == "en0")
        #expect(auto?.downloadBytesPerSecond == 103)
        #expect(auto?.uploadBytesPerSecond == 211)
    }

    @Test("Automatic does not count a VPN tunnel twice")
    @MainActor
    func automaticExcludesVPN() {
        func iface(_ name: String, vpn: Bool, down: Double) -> NetworkInterfaceSample {
            NetworkInterfaceSample(
                name: name, isUp: true, isLoopback: false, isVPN: vpn, ipv4Addresses: [], ipv6Addresses: [],
                downloadBytesPerSecond: down, uploadBytesPerSecond: 0, receivedBytes: 0, sentBytes: 0,
                inputErrors: 0, outputErrors: 0)
        }
        let sample = NetworkSample(
            timestamp: Date(),
            interfaces: [iface("en0", vpn: false, down: 100), iface("utun4", vpn: true, down: 100),
                         iface("bridge100", vpn: false, down: 7)],
            primaryInterface: "en0", router: nil, dnsServers: [], wifi: nil, publicIP: nil)
        // The tunnel's bytes already crossed en0; counting them again would double the reading.
        #expect(sample.interface(named: nil)?.downloadBytesPerSecond == 107)
        // All interfaces is the explicit everything-including-tunnels total.
        #expect(sample.interface(named: NetworkSample.allInterfacesName)?.downloadBytesPerSecond == 207)
    }

    @Test("The aggregate selection is distinct from every real interface")
    func aggregateNameIsReserved() {
        // BSD device names are alphanumeric, so the reserved name cannot name a real interface.
        let real = ["en0", "lo0", "utun4", "vmenet0", "bridge100", "awdl0"]
        #expect(!real.contains(NetworkSample.allInterfacesName))
        #expect(NetworkSample.allInterfacesName.hasPrefix("__"))

        // With nothing active there is nothing to total, so the selection resolves to no reading
        // rather than to a stale or fabricated one.
        let empty = NetworkSample(
            timestamp: Date(), interfaces: [], primaryInterface: nil, router: nil, dnsServers: [],
            wifi: nil, publicIP: nil)
        #expect(empty.interface(named: NetworkSample.allInterfacesName) == nil)
    }
}
