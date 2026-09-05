import AppKit
import MenuBarStatsCore
import SwiftUI

/// Live capacity and physical I/O detail for the Disks status item.
public struct DiskDropdownView: View {
    /// Fixed hosted content width; height follows the content.
    public static let contentSize = CGSize(width: 380, height: 540)

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
        let accent = ModuleAccent.resolve(settingsStore.settings, module: .disks)
        let readAccent = ModuleAccent(primary: accent.primary, secondary: accent.primary.opacity(0.7))
        let writeAccent = ModuleAccent(primary: accent.secondary, secondary: accent.secondary.opacity(0.7))
        let rates = sample?.totalRates ?? (read: 0, write: 0)
        let selected = sample?.selectedVolume(settings: settings)

        DropdownScaffold(size: Self.contentSize) {
            HeroHeader(
                symbolName: "internaldrive.fill",
                title: "Disks",
                subtitle: selected.map {
                    "\($0.name)  ·  "
                        + "\(DiskValueFormatter.capacity($0.availableBytes, unitSystem: settings.unitSystem)) free"
                }
                    ?? "Waiting for the first sample",
                value: selected.map { String(format: "%.0f%%", $0.usedPercent) } ?? "—",
                accent: accent
            )

            GlassCard(tint: accent.primary) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        DiskRateTile(
                            symbol: "arrow.down.circle.fill", label: "Read",
                            value: DiskValueFormatter.rate(rates.read, unitSystem: settings.unitSystem),
                            color: accent.primary)
                        DiskRateTile(
                            symbol: "arrow.up.circle.fill", label: "Write",
                            value: DiskValueFormatter.rate(rates.write, unitSystem: settings.unitSystem),
                            color: accent.secondary)
                    }
                    DiskHistoryGraph(
                        samples: store.history.recent(300), readAccent: readAccent, writeAccent: writeAccent
                    )
                    .frame(height: 90)
                }
            }

            if let sample {
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("Volumes")
                        ForEach(sample.visibleVolumes(settings: settings), id: \.id) { volume in
                            VolumeRow(
                                volume: volume, settings: settings, accent: accent,
                                criticalColor: AppearanceColorResolver.critical(settingsStore.settings, module: .disks)
                            ) {
                                eject(volume)
                            }
                        }
                    }
                }

                if !sample.devices.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel("Physical disks")
                            ForEach(sample.devices, id: \.bsdName) { device in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(device.model ?? device.bsdName)
                                            .font(.callout.weight(.semibold))
                                            .lineLimit(1)
                                        Spacer()
                                        Chip(text: device.bsdName, color: .secondary, symbol: "internaldrive")
                                    }
                                    MetricRow(
                                        label: "Read",
                                        value: DiskValueFormatter.rate(
                                            device.readBytesPerSecond, unitSystem: settings.unitSystem),
                                        symbol: "arrow.down", tint: accent.primary)
                                    MetricRow(
                                        label: "Write",
                                        value: DiskValueFormatter.rate(
                                            device.writeBytesPerSecond, unitSystem: settings.unitSystem),
                                        symbol: "arrow.up", tint: accent.secondary)
                                    MetricRow(
                                        label: "Operations",
                                        value: String(
                                            format: "%.1f read · %.1f write /s", device.readOperationsPerSecond,
                                            device.writeOperationsPerSecond),
                                        symbol: "arrow.triangle.2.circlepath",
                                        tint: accent.primary
                                    )
                                }
                            }
                        }
                    }
                }
            } else {
                GlassCard {
                    ContentUnavailableView("Disk data unavailable", systemImage: "internaldrive")
                }
            }

            if let ejectError {
                Label(ejectError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
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

private struct VolumeRow: View {
    let volume: DiskVolumeSample
    let settings: DiskSettings
    let accent: ModuleAccent
    let criticalColor: Color
    let eject: () -> Void
    @State private var isHovering = false

    var body: some View {
        let isCritical = volume.usedPercent >= 90
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(
                    systemName: volume.isEjectable || volume.isRemovable ? "externaldrive.fill" : "internaldrive.fill"
                )
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(accent.primary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(volume.name).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(volume.mountPoint)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(String(format: "%.0f%%", volume.usedPercent))
                    .font(BarometerDesign.valueFont)
                    .foregroundStyle(isCritical ? criticalColor : .primary)
                    .contentTransition(.numericText())
                if volume.isEjectable || volume.isRemovable {
                    Button(action: eject) {
                        Image(systemName: "eject.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Eject \(volume.name)")
                    .opacity(isHovering ? 1 : 0.45)
                }
            }
            CapsuleBar(
                fraction: volume.usedPercent / 100,
                gradient: isCritical
                    ? LinearGradient(
                        colors: [criticalColor, criticalColor.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
                    : accent.horizontalGradient,
                height: 6,
                glowColor: isCritical ? criticalColor : accent.primary
            )
            HStack {
                Text(String(format: "%.0f%% used", volume.usedPercent))
                Spacer()
                Text(DiskValueFormatter.capacity(volume.availableBytes, unitSystem: settings.unitSystem) + " free")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(8)
        .insetPlate()
        .onHover { isHovering = $0 }
    }
}

private struct DiskRateTile: View {
    let symbol: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 22))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.3), value: value)
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .insetPlate()
    }
}

private struct DiskHistoryGraph: View {
    let samples: [HistoryEntry<DiskSample.GraphValue>]
    let readAccent: ModuleAccent
    let writeAccent: ModuleAccent

    var body: some View {
        let values = samples.suffix(300).map { entry in
            entry.value
        }
        let maximum = DiskSample.graphScale(for: values)
        MirroredAreaGraph(
            upper: values.map { min(1, $0.read / maximum) },
            lower: values.map { min(1, $0.write / maximum) },
            upperAccent: readAccent,
            lowerAccent: writeAccent
        )
    }
}
