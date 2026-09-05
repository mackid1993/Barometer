import MenuBarStatsCore
import SwiftUI

/// GPU utilization, memory, frequency, temperature, and power detail.
public struct GPUDropdownView: View {
    /// Fixed hosted content width; height follows the content.
    public static let contentSize = CGSize(width: 380, height: 520)

    private let store: ModuleStore<GPUSample>
    private let settingsStore: SettingsStore
    @State private var range: HistoryRange = .fiveMinutes

    /// Creates the GPU dropdown.
    public init(store: ModuleStore<GPUSample>, settingsStore: SettingsStore) {
        self.store = store
        self.settingsStore = settingsStore
        _range = State(initialValue: .fiveMinutes)
    }

    init(store: ModuleStore<GPUSample>, settingsStore: SettingsStore, initialRange: HistoryRange) {
        self.store = store
        self.settingsStore = settingsStore
        _range = State(initialValue: initialRange)
    }

    public var body: some View {
        let sample = store.latestSample
        let _ = store.revision
        let accent = ModuleAccent.resolve(settingsStore.settings, module: .gpu)
        let end = sample?.timestamp ?? Date()
        let cutoff = end.addingTimeInterval(-range.duration)
        let graph = TimelineGraphData.make(
            entries: store.history.downsampled(to: 300, since: cutoff),
            endingAt: end,
            duration: range.duration,
            value: { min(1, max(0, $0.deviceUtilizationPercent / 100)) }
        )

        DropdownScaffold(size: Self.contentSize) {
            HeroHeader(
                symbolName: "square.stack.3d.up.fill",
                title: "GPU",
                subtitle: sample?.name ?? "Waiting for the first sample",
                value: sample.map { String(format: "%.1f%%", $0.deviceUtilizationPercent) } ?? "—",
                accent: accent
            )

            GlassCard(tint: accent.primary) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("History") {
                        CapsulePicker(
                            options: HistoryRange.allCases,
                            selection: $range,
                            label: \.rawValue,
                            accent: accent
                        )
                    }
                    AreaGraph(values: graph.values, accent: accent, xPositions: graph.xPositions)
                        .frame(height: 96)
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 9) {
                    SectionLabel("Utilization")
                    UtilizationRow(label: "Device", percent: sample?.deviceUtilizationPercent, accent: accent)
                    UtilizationRow(label: "Renderer", percent: sample?.rendererUtilizationPercent, accent: accent)
                    UtilizationRow(label: "Tiler", percent: sample?.tilerUtilizationPercent, accent: accent)
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Memory")
                    if let used = sample?.memoryInUseBytes, let allocated = sample?.memoryAllocatedBytes, allocated > 0
                    {
                        CapsuleBar(
                            fraction: Double(min(used, allocated)) / Double(allocated),
                            gradient: accent.horizontalGradient,
                            height: 7,
                            glowColor: accent.primary
                        )
                        HStack(spacing: 8) {
                            StatTile(
                                symbol: "memorychip", label: "In use", value: Self.bytes(used), tint: accent.primary)
                            StatTile(
                                symbol: "square.dashed", label: "Allocated", value: Self.bytes(allocated),
                                tint: accent.secondary)
                        }
                    } else {
                        Text("Unavailable").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Hardware")
                    HStack(spacing: 8) {
                        StatTile(
                            symbol: "waveform.path.ecg", label: "Frequency", value: frequency(sample?.frequencyMHz),
                            tint: accent.primary)
                        StatTile(symbol: "bolt.fill", label: "Power", value: power(sample?.powerWatts), tint: .yellow)
                        StatTile(
                            symbol: "thermometer.medium", label: "Temperature",
                            value: temperature(sample?.temperatureCelsius), tint: .orange)
                    }
                }
            }
        }
    }

    private func frequency(_ value: Double?) -> String {
        value.map { String(format: "%.0f MHz", $0) } ?? "—"
    }

    private func power(_ value: Double?) -> String {
        value.map { String(format: "%.2f W", $0) } ?? "—"
    }

    private func temperature(_ celsius: Double?) -> String {
        guard let celsius else { return "—" }
        let reading = SensorReading(
            id: "gpu:temperature",
            name: "GPU Temperature",
            shortName: "GPU",
            rawName: "gpu",
            kind: .temperature,
            source: .ioReport,
            value: celsius,
            unit: .celsius
        )
        return SensorValueFormatter.string(
            reading,
            temperatureUnit: settingsStore.settings.sensorTemperatureUnit,
            decimalPlaces: settingsStore.settings.sensors.decimalPlaces
        )
    }

    private static func bytes(_ bytes: UInt64) -> String {
        String(format: "%.2f GiB", Double(bytes) / 1_073_741_824)
    }
}

private struct UtilizationRow: View {
    let label: String
    let percent: Double?
    let accent: ModuleAccent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Text(percent.map { String(format: "%.1f%%", $0) } ?? "—")
                    .font(BarometerDesign.valueFont)
                    .contentTransition(.numericText())
            }
            CapsuleBar(
                fraction: (percent ?? 0) / 100,
                gradient: accent.horizontalGradient,
                height: 5,
                glowColor: accent.primary
            )
        }
    }
}
