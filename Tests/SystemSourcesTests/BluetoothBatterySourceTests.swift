import Testing
@testable import SystemSources

@Suite("BluetoothBatterySourceTests")
struct BluetoothBatterySourceTests {
    @Test("known component keys become plain-language levels")
    func componentParsing() {
        let snapshot = BluetoothBatterySource.snapshot(
            properties: [
                "Product": "AirPods Pro",
                "DeviceAddress": "AA-BB-CC-DD-EE-FF",
                "BatteryPercentLeft": 81,
                "BatteryPercentRight": 76,
                "BatteryPercentCase": 52,
            ],
            registryIdentifier: 10
        )

        #expect(snapshot?.id == "AA-BB-CC-DD-EE-FF")
        #expect(snapshot?.name == "AirPods Pro")
        #expect(snapshot?.levels.map(\.component) == [.left, .right, .case])
        #expect(snapshot?.levels.map(\.percent) == [81, 76, 52])
    }

    @Test("invalid and absent values do not create a device")
    func invalidValues() {
        #expect(BluetoothBatterySource.snapshot(
            properties: ["Product": "Keyboard"],
            registryIdentifier: 11
        ) == nil)
        #expect(BluetoothBatterySource.snapshot(
            properties: ["Product": "Mouse", "BatteryPercent": 255],
            registryIdentifier: 12
        ) == nil)
    }
}
