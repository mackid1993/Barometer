import AppKit
import MenuBarStatsCore
import SwiftUI

/// Live capacity and physical I/O detail for the Disks status item.
public struct DiskDropdownView: View {
    private let store: ModuleStore<DiskSample>
    private let settingsStore: SettingsStore
    @State private var ejectError: String?

    /// Creates a Disk dropdown backed by the supplied observable store.
    public init(store: ModuleStore<DiskSample>, settingsStore: SettingsStore) {
        self.store = store
        self.settingsStore = settingsStore
    }

    public var body: some View {
        let sample = store.latestSample
        let settings = settingsStore.settings.disks
        let _ = store.revision

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header(sample: sample, settings: settings)

                Text("ACTIVITY").diskSectionLabel()
                DiskHistoryGraph(
                    samples: store.history.entries,
                    readColor: AppearanceColorResolver.graph(settingsStore.settings, module: .disks),
                    writeColor: AppearanceColorResolver.fill(settingsStore.settings, module: .disks)
                )
                    .frame(height: 86)

                if let sample {
                    volumeList(sample: sample, settings: settings)
                    deviceList(sample: sample, settings: settings)
                } else {
                    ContentUnavailableView("Disk data unavailable", systemImage: "internaldrive")
                }

                if let ejectError {
                    Text(ejectError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(14)
        }
        .frame(width: 380, height: 520)
    }

    private func header(sample: DiskSample?, settings: DiskSettings) -> some View {
        let rates = aggregateRates(sample)
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Disks").font(.headline)
                Spacer()
                Text(sample?.selectedVolume(settings: settings)?.name ?? "Unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 18) {
                rateSummary(
                    symbol: "arrow.down",
                    label: "Read",
                    value: rates.read,
                    unitSystem: settings.unitSystem,
                    color: AppearanceColorResolver.graph(settingsStore.settings, module: .disks)
                )
                rateSummary(
                    symbol: "arrow.up",
                    label: "Write",
                    value: rates.write,
                    unitSystem: settings.unitSystem,
                    color: AppearanceColorResolver.fill(settingsStore.settings, module: .disks)
                )
            }
        }
    }

    private func rateSummary(
        symbol: String,
        label: String,
        value: Double,
        unitSystem: DiskUnitSystem,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(label, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(color)
            Text(DiskValueFormatter.rate(value, unitSystem: unitSystem))
                .font(.system(.title3, design: .rounded).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func volumeList(sample: DiskSample, settings: DiskSettings) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("VOLUMES").diskSectionLabel()
            ForEach(sample.visibleVolumes(settings: settings), id: \.id) { volume in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(volume.name).font(.subheadline.weight(.semibold))
                            Text(volume.mountPoint)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if volume.isEjectable || volume.isRemovable {
                            Button {
                                eject(volume)
                            } label: {
                                Image(systemName: "eject")
                            }
                            .buttonStyle(.plain)
                            .help("Eject \(volume.name)")
                        }
                    }
                    ProgressView(value: volume.usedPercent, total: 100)
                        .tint(volume.usedPercent >= 90 ? .red : .accentColor)
                    HStack {
                        Text(String(format: "%.0f%% used", volume.usedPercent))
                        Spacer()
                        Text(
                            DiskValueFormatter.capacity(volume.availableBytes, unitSystem: settings.unitSystem) + " free"
                        )
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func deviceList(sample: DiskSample, settings: DiskSettings) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("PHYSICAL DISKS").diskSectionLabel()
            ForEach(sample.devices, id: \.bsdName) { device in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(device.model ?? device.bsdName)
                        Spacer()
                        Text(device.bsdName).foregroundStyle(.secondary)
                    }
                    .font(.caption.weight(.semibold))
                    DiskMetricRow(
                        label: "Read",
                        value: DiskValueFormatter.rate(
                            device.readBytesPerSecond,
                            unitSystem: settings.unitSystem
                        )
                    )
                    DiskMetricRow(
                        label: "Write",
                        value: DiskValueFormatter.rate(
                            device.writeBytesPerSecond,
                            unitSystem: settings.unitSystem
                        )
                    )
                    DiskMetricRow(
                        label: "Operations",
                        value: String(
                            format: "%.1f read · %.1f write /s",
                            device.readOperationsPerSecond,
                            device.writeOperationsPerSecond
                        )
                    )
                }
            }
        }
    }

    private func aggregateRates(_ sample: DiskSample?) -> (read: Double, write: Double) {
        sample?.devices.reduce(into: (read: 0.0, write: 0.0)) { result, device in
            result.read += device.readBytesPerSecond
            result.write += device.writeBytesPerSecond
        } ?? (0, 0)
    }

    private func eject(_ volume: DiskVolumeSample) {
        ejectError = nil
        let url = URL(fileURLWithPath: volume.mountPoint, isDirectory: true)
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: url)
        } catch {
            ejectError = "Unable to eject \(volume.name): \(error.localizedDescription)"
        }
    }
}

private struct DiskHistoryGraph: View {
    let samples: [HistoryEntry<DiskSample>]
    let readColor: Color
    let writeColor: Color

    var body: some View {
        Canvas { context, size in
            let values = samples.suffix(300).map { entry in
                entry.value.devices.reduce(into: (read: 0.0, write: 0.0)) { result, device in
                    result.read += device.readBytesPerSecond
                    result.write += device.writeBytesPerSecond
                }
            }
            guard values.count > 1 else {
                return
            }
            let maximum = max(1, values.reduce(0) { max($0, $1.read, $1.write) } * 1.1)
            let center = size.height / 2
            draw(
                values.map(\.read), maximum: maximum, baseline: center, direction: -1,
                color: readColor, in: &context, size: size
            )
            draw(
                values.map(\.write), maximum: maximum, baseline: center, direction: 1,
                color: writeColor, in: &context, size: size
            )
        }
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
    }

    private func draw(
        _ values: [Double],
        maximum: Double,
        baseline: CGFloat,
        direction: CGFloat,
        color: Color,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        var path = Path()
        for (index, value) in values.enumerated() {
            let x = CGFloat(index) / CGFloat(max(1, values.count - 1)) * size.width
            let amplitude = min(1, max(0, value / maximum)) * (size.height / 2)
            let point = CGPoint(x: x, y: baseline + direction * amplitude)
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        context.stroke(path, with: .color(color), lineWidth: 1.5)
    }
}

private struct DiskMetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.caption)
    }
}

private extension View {
    func diskSectionLabel() -> some View {
        font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
    }
}
