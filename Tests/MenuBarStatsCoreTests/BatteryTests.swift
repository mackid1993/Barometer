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

    @Test("battery time formatting reserves a stable width and rejects missing estimates")
    func formatsTimeEstimates() {
        #expect(BatteryTimeFormatter.compact(minutes: 495) == "8:15")
        #expect(BatteryTimeFormatter.compact(minutes: 5) == "0:05")
        #expect(BatteryTimeFormatter.compact(minutes: 725) == "12:05")
        #expect(BatteryTimeFormatter.compact(minutes: nil) == "—")
        #expect(BatteryTimeFormatter.compact(minutes: 0) == "—")
        #expect(BatteryTimeFormatter.reservedCompact.count == 5)

        #expect(BatteryTimeFormatter.long(minutes: 495) == "8 hr 15 min")
        #expect(BatteryTimeFormatter.long(minutes: 120) == "2 hr")
        #expect(BatteryTimeFormatter.long(minutes: 45) == "45 min")
        #expect(BatteryTimeFormatter.long(minutes: nil) == nil)

        #expect(BatteryTimeFormatter.detail(minutes: nil, isEstimating: true) == "Calculating…")
        #expect(BatteryTimeFormatter.detail(minutes: nil, isEstimating: false) == "—")
    }

    @Test("the sample reports the estimate matching its charge direction")
    func selectsDirectionalEstimate() {
        let discharging = BatterySample(
            snapshot: snapshot(isExternalConnected: false, isCharging: false, toEmpty: 495, toFull: nil)
        )
        #expect(discharging.remainingMinutes == 495)
        #expect(discharging.isEstimatingTime)

        let charging = BatterySample(
            snapshot: snapshot(isExternalConnected: true, isCharging: true, toEmpty: nil, toFull: 62)
        )
        #expect(charging.remainingMinutes == 62)
        #expect(charging.isEstimatingTime)

        // A full battery on the adapter has nothing to estimate; it is not "calculating".
        let full = BatterySample(
            snapshot: snapshot(isExternalConnected: true, isCharging: false, toEmpty: nil, toFull: nil)
        )
        #expect(full.remainingMinutes == nil)
        #expect(!full.isEstimatingTime)
    }

    private func snapshot(
        isExternalConnected: Bool,
        isCharging: Bool,
        toEmpty: Int?,
        toFull: Int?
    ) -> BatterySnapshot {
        BatterySnapshot(
            name: "Internal Battery",
            chargePercent: 85,
            state: isCharging ? .charging : (isExternalConnected ? .full : .discharging),
            isExternalConnected: isExternalConnected,
            isCharging: isCharging,
            isFullyCharged: !isCharging && isExternalConnected,
            healthPercent: nil,
            cycleCount: nil,
            temperatureCelsius: nil,
            voltageVolts: nil,
            amperageAmps: nil,
            wattageWatts: nil,
            condition: nil,
            adapter: nil,
            isLowPowerModeEnabled: false,
            timeToEmptyMinutes: toEmpty,
            timeToFullMinutes: toFull
        )
    }
}
