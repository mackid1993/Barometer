import MenuBarStatsCore
import SwiftUI
import SystemSources

/// Battery charge history, health, electrical, thermal, and adapter detail.
public struct BatteryDropdownView: View {
    /// Fixed hosted content width; height follows the content.
    public static let contentSize = CGSize(width: 380, height: 560)

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
        let accent = ModuleAccent.resolve(settingsStore.settings, module: .battery)
        let history = store.history.entries.suffix(720).map { min(1, max(0, $0.value.chargePercent / 100)) }

        DropdownScaffold(size: Self.contentSize) {
            HeroHeader(
                symbolName: sample.map(BatteryMenuBarPresenter.symbolName) ?? "battery.0percent",
                title: "Battery",
                subtitle: sample.map(Self.state) ?? "Waiting for the first sample",
                value: nil,
                accent: accent
            )

            GlassCard(tint: accent.primary) {
                HStack(spacing: 14) {
                    ProgressRing(fraction: (sample?.chargePercent ?? 0) / 100, accent: accent, lineWidth: 8, size: 86) {
                        VStack(spacing: 0) {
                            Text(sample.map { String(format: "%.0f", $0.chargePercent) } ?? "—")
                                .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                                .contentTransition(.numericText())
                            Text("%").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        StatTile(
                            symbol: "heart.fill", label: "Health", value: percent(sample?.healthPercent),
                            tint: accent.primary)
                        StatTile(
                            symbol: "arrow.triangle.2.circlepath", label: "Cycles",
                            value: sample?.cycleCount.map(String.init) ?? "—", tint: accent.secondary)
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Charge history") {
                        if let sample {
                            Chip(
                                text: sample.isLowPowerModeEnabled ? "Low Power Mode" : "Normal power",
                                color: sample.isLowPowerModeEnabled ? .orange : accent.primary,
                                symbol: sample.isLowPowerModeEnabled ? "battery.25percent" : "bolt.fill"
                            )
                        }
                    }
                    AreaGraph(values: history, accent: accent)
                        .frame(height: 80)
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Power") {
                        Text(sample?.condition ?? "")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        StatTile(
                            symbol: "thermometer.medium", label: "Temperature",
                            value: temperature(sample?.temperatureCelsius), tint: .orange)
                        StatTile(
                            symbol: "waveform.path", label: "Voltage",
                            value: measurement(sample?.voltageVolts, format: "%.3f V"), tint: .purple)
                        StatTile(
                            symbol: "arrow.right.circle", label: "Current",
                            value: measurement(sample?.amperageAmps, format: "%+.3f A"), tint: .mint)
                        StatTile(
                            symbol: "bolt.fill", label: "Power",
                            value: measurement(sample?.wattageWatts, format: "%+.2f W"), tint: .yellow)
                        StatTile(
                            symbol: "hourglass",
                            label: sample?.isCharging == true ? "Until full" : "Remaining",
                            value: sample.map {
                                BatteryTimeFormatter.detail(
                                    minutes: $0.remainingMinutes,
                                    isEstimating: $0.isEstimatingTime
                                )
                            } ?? "—",
                            tint: accent.primary)
                    }
                }
            }

            if let adapter = sample?.adapter {
                GlassCard {
                    VStack(alignment: .leading, spacing: 2) {
                        SectionLabel("Power adapter")
                        MetricRow(
                            label: "Name", value: adapter.name ?? adapter.description ?? "Connected",
                            symbol: "powerplug.fill", tint: accent.primary)
                        MetricRow(
                            label: "Rating", value: measurement(adapter.watts, format: "%.0f W"), symbol: "bolt.fill",
                            tint: .yellow)
                        MetricRow(
                            label: "Connection", value: adapter.isWireless == true ? "Wireless" : "Wired",
                            symbol: adapter.isWireless == true ? "wave.3.right" : "cable.connector",
                            tint: accent.secondary)
                    }
                }
            }

            if settingsStore.settings.battery.showsBluetoothDevices,
                let devices = sample?.bluetoothDevices,
                !devices.isEmpty
            {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Bluetooth batteries")
                        ForEach(devices) { device in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(device.name).font(.callout.weight(.medium)).lineLimit(1)
                                ForEach(device.levels, id: \.component) { level in
                                    HStack(spacing: 8) {
                                        Text(level.component.rawValue)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .frame(width: 60, alignment: .leading)
                                        CapsuleBar(
                                            fraction: Double(level.percent) / 100, gradient: accent.horizontalGradient,
                                            height: 5, glowColor: accent.primary)
                                        Text("\(level.percent)%")
                                            .font(.caption.monospacedDigit())
                                            .frame(width: 36, alignment: .trailing)
                                    }
                                }
                            }
                            .padding(8)
                            .insetPlate()
                        }
                    }
                }
            }
        }
    }

    private func temperature(_ celsius: Double?) -> String {
        guard let celsius else { return "—" }
        let unit = settingsStore.settings.sensorTemperatureUnit
        let value = unit == .fahrenheit ? celsius * 9 / 5 + 32 : celsius
        return String(format: "%.1f%@", value, unit == .fahrenheit ? "°F" : "°C")
    }

    private func percent(_ value: Double?) -> String {
        value.map { String(format: "%.1f%%", $0) } ?? "—"
    }

    private func measurement(_ value: Double?, format: String) -> String {
        value.map { String(format: format, $0) } ?? "—"
    }

    private static func state(_ sample: BatterySample) -> String {
        let name: String
        switch sample.state {
        case .charging: name = "Charging"
        case .discharging: name = "Using Battery"
        case .full: name = "Fully Charged"
        case .onAC: name = "Connected to Power"
        }
        guard let remaining = BatteryTimeFormatter.long(minutes: sample.remainingMinutes) else {
            return sample.isEstimatingTime ? "\(name) · Calculating…" : name
        }
        return sample.isCharging ? "\(name) · \(remaining) to full" : "\(name) · \(remaining) remaining"
    }
}
