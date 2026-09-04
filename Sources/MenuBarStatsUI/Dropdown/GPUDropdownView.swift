import MenuBarStatsCore
import SwiftUI

/// GPU utilization, memory, frequency, temperature, and power detail.
public struct GPUDropdownView: View {
    private let store: ModuleStore<GPUSample>
    private let settingsStore: SettingsStore

    /// Creates the GPU dropdown.
    public init(store: ModuleStore<GPUSample>, settingsStore: SettingsStore) {
        self.store = store
        self.settingsStore = settingsStore
    }

    public var body: some View {
        let sample = store.latestSample
        let _ = store.revision
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("GPU").font(.headline)
                    Text(sample?.name ?? "Unavailable").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(sample.map { String(format: "%.1f%%", $0.deviceUtilizationPercent) } ?? "—")
                    .font(.system(.title2, design: .rounded).monospacedDigit().weight(.semibold))
            }

            GPUHistoryGraph(
                samples: store.history.entries,
                color: AppearanceColorResolver.graph(settingsStore.settings, module: .gpu)
            )
                .frame(height: 110)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))

            Text("UTILIZATION").gpuSectionLabel()
            GPUMetricRow(label: "Device", value: percent(sample?.deviceUtilizationPercent))
            GPUMetricRow(label: "Renderer", value: percent(sample?.rendererUtilizationPercent))
            GPUMetricRow(label: "Tiler", value: percent(sample?.tilerUtilizationPercent))

            Divider()
            Text("MEMORY").gpuSectionLabel()
            if let used = sample?.memoryInUseBytes, let allocated = sample?.memoryAllocatedBytes, allocated > 0 {
                ProgressView(value: Double(min(used, allocated)), total: Double(allocated))
                GPUMetricRow(label: "In use", value: Self.bytes(used))
                GPUMetricRow(label: "Allocated", value: Self.bytes(allocated))
            } else {
                Text("Unavailable").font(.caption).foregroundStyle(.secondary)
            }

            Divider()
            Text("HARDWARE").gpuSectionLabel()
            GPUMetricRow(label: "Frequency", value: frequency(sample?.frequencyMHz))
            GPUMetricRow(label: "Power", value: power(sample?.powerWatts))
            GPUMetricRow(label: "Temperature", value: temperature(sample?.temperatureCelsius))
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 380, height: 500)
    }

    private func percent(_ value: Double?) -> String {
        value.map { String(format: "%.1f%%", $0) } ?? "Unavailable"
    }

    private func frequency(_ value: Double?) -> String {
        value.map { String(format: "%.0f MHz", $0) } ?? "Unavailable"
    }

    private func power(_ value: Double?) -> String {
        value.map { String(format: "%.2f W", $0) } ?? "Unavailable"
    }

    private func temperature(_ celsius: Double?) -> String {
        guard let celsius else { return "Unavailable" }
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

private struct GPUMetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.subheadline)
    }
}

private struct GPUHistoryGraph: View {
    let samples: [HistoryEntry<GPUSample>]
    let color: Color

    var body: some View {
        Canvas { context, size in
            let values = samples.suffix(300).map { min(1, max(0, $0.value.deviceUtilizationPercent / 100)) }
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
    func gpuSectionLabel() -> some View {
        font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
    }
}
