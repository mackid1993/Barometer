import MenuBarStatsCore
import SwiftUI
import SystemSources

/// Battery charge history, health, electrical, thermal, and adapter detail.
public struct BatteryDropdownView: View {
    private let store: ModuleStore<BatterySample>
    private let settingsStore: SettingsStore

    /// Creates the Battery dropdown.
    public init(store: ModuleStore<BatterySample>, settingsStore: SettingsStore) {
        self.store = store
        self.settingsStore = settingsStore
    }

    public var body: some View {
        let sample = store.latestSample
        let _ = store.revision
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: sample.map(BatteryMenuBarPresenter.symbolName) ?? "battery.0percent")
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Battery").font(.headline)
                        Text(sample.map(Self.state) ?? "Unavailable")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(sample.map { String(format: "%.0f%%", $0.chargePercent) } ?? "—")
                        .font(.system(.title2, design: .rounded).monospacedDigit().weight(.semibold))
                }

                BatteryHistoryGraph(
                    samples: store.history.entries,
                    color: AppearanceColorResolver.graph(settingsStore.settings, module: .battery)
                )
                    .frame(height: 88)
                    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))

                Text("STATUS").batterySectionLabel()
                BatteryMetricRow(label: "Time remaining", value: time(sample?.timeRemainingMinutes))
                BatteryMetricRow(
                    label: "Low Power Mode",
                    value: sample.map { $0.isLowPowerModeEnabled ? "On" : "Off" } ?? "Unavailable"
                )

                Divider()
                Text("HEALTH").batterySectionLabel()
                BatteryMetricRow(label: "Condition", value: sample?.condition ?? "Unavailable")
                BatteryMetricRow(label: "Maximum capacity", value: percent(sample?.healthPercent))
                BatteryMetricRow(label: "Cycle count", value: sample?.cycleCount.map(String.init) ?? "Unavailable")

                Divider()
                Text("POWER").batterySectionLabel()
                BatteryMetricRow(label: "Temperature", value: temperature(sample?.temperatureCelsius))
                BatteryMetricRow(label: "Voltage", value: measurement(sample?.voltageVolts, format: "%.3f V"))
                BatteryMetricRow(label: "Current", value: measurement(sample?.amperageAmps, format: "%+.3f A"))
                BatteryMetricRow(label: "Power", value: measurement(sample?.wattageWatts, format: "%+.2f W"))

                if let adapter = sample?.adapter {
                    Divider()
                    Text("POWER ADAPTER").batterySectionLabel()
                    BatteryMetricRow(label: "Name", value: adapter.name ?? adapter.description ?? "Connected")
                    BatteryMetricRow(label: "Rating", value: measurement(adapter.watts, format: "%.0f W"))
                    BatteryMetricRow(label: "Connection", value: adapter.isWireless == true ? "Wireless" : "Wired")
                }

                if settingsStore.settings.battery.showsBluetoothDevices,
                   let devices = sample?.bluetoothDevices,
                   !devices.isEmpty {
                    Divider()
                    Text("BLUETOOTH BATTERIES").batterySectionLabel()
                    ForEach(devices) { device in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(device.name).font(.subheadline.weight(.medium)).lineLimit(1)
                            ForEach(device.levels, id: \.component) { level in
                                BatteryMetricRow(label: level.component.rawValue, value: "\(level.percent)%")
                            }
                        }
                    }
                }

            }
            .padding(14)
        }
        .frame(width: 360, height: 520)
    }

    private func temperature(_ celsius: Double?) -> String {
        guard let celsius else { return "Unavailable" }
        let unit = settingsStore.settings.sensorTemperatureUnit
        let value = unit == .fahrenheit ? celsius * 9 / 5 + 32 : celsius
        return String(format: "%.1f%@", value, unit == .fahrenheit ? "°F" : "°C")
    }

    private func percent(_ value: Double?) -> String {
        value.map { String(format: "%.1f%%", $0) } ?? "Unavailable"
    }

    private func time(_ minutes: Int?) -> String {
        guard let minutes else { return "Unavailable" }
        return "\(minutes / 60) hr \(minutes % 60) min"
    }

    private func measurement(_ value: Double?, format: String) -> String {
        value.map { String(format: format, $0) } ?? "Unavailable"
    }

    private static func state(_ sample: BatterySample) -> String {
        switch sample.state {
        case .charging: "Charging"
        case .discharging: "Using Battery"
        case .full: "Fully Charged"
        case .onAC: "Connected to Power"
        }
    }
}

private struct BatteryMetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit().lineLimit(1)
        }
        .font(.subheadline)
    }
}

private struct BatteryHistoryGraph: View {
    let samples: [HistoryEntry<BatterySample>]
    let color: Color

    var body: some View {
        Canvas { context, size in
            let values = samples.suffix(720).map { min(1, max(0, $0.value.chargePercent / 100)) }
            guard values.count > 1 else { return }
            var path = Path()
            for (index, value) in values.enumerated() {
                let x = CGFloat(index) / CGFloat(values.count - 1) * size.width
                let y = (1 - CGFloat(value)) * size.height
                index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
            }
            context.stroke(path, with: .color(color), lineWidth: 1.6)
        }
    }
}

private extension View {
    func batterySectionLabel() -> some View {
        font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
    }
}
