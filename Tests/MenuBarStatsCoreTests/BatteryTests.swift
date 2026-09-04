import Foundation
import MenuBarStatsCore
import SystemSources
import Testing

@Suite("BatteryTests")
struct BatteryTests {
    @Test("battery settings use conservative production defaults")
    func settingsDefaults() {
        let settings = BatterySettings()

        #expect(settings.showsWhenConnectedToPower)
        #expect(settings.lowBatteryThresholdPercent == 20)
        #expect(settings.showsBluetoothDevices)
    }

    @Test("monitor maps the normalized system snapshot")
    func monitorMapping() async throws {
        let snapshot = BatterySnapshot(
            name: "Internal Battery",
            chargePercent: 42.5,
            state: .discharging,
            isExternalConnected: false,
            isCharging: false,
            isFullyCharged: false,
            healthPercent: 96.2,
            cycleCount: 51,
            temperatureCelsius: 31.5,
            voltageVolts: 12.4,
            amperageAmps: -1.25,
            wattageWatts: -15.5,
            condition: "Good",
            adapter: nil,
            isLowPowerModeEnabled: true
        )
        let device = BluetoothBatterySnapshot(
            id: "headphones",
            name: "Headphones",
            levels: [BluetoothBatteryLevel(component: .device, percent: 75)]
        )
        let monitor = BatteryMonitor(
            read: { snapshot },
            isAvailable: { true },
            bluetoothDevices: { [device] }
        )

        #expect(await monitor.isAvailable)
        let sample = try await monitor.sample()
        #expect(sample.chargePercent == 42.5)
        #expect(sample.state == .discharging)
        #expect(sample.isLowPowerModeEnabled)
        #expect(sample.bluetoothDevices == [device])
    }
}
