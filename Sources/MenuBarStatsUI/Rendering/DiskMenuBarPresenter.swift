import AppKit
import MenuBarStatsCore

/// Converts Disk samples and preferences into stable image-only status-item content.
@MainActor
enum DiskMenuBarPresenter {
    static func content(
        sample: DiskSample?,
        history: [HistoryEntry<DiskSample.GraphValue>],
        moduleSettings: ModuleSettings,
        diskSettings: DiskSettings,
        context: RenderContext
    ) -> StatusItemContent {
        let volume = sample?.selectedVolume(settings: diskSettings)
        let rates = sample.map(aggregateRates) ?? (read: 0, write: 0)
        let renderer: any MenuBarRenderer
        switch moduleSettings.mode {
        case "freePercentage":
            let freePercent = volume.map(Self.freePercent)
            renderer = TextRenderer(
                text: freePercent.map { String(format: "%.0f%%", $0) } ?? "—",
                reservedText: moduleSettings.usesFixedWidth ? "100%" : nil
            )
        case "freeBytes":
            let free = volume.map {
                DiskValueFormatter.capacity($0.availableBytes, unitSystem: diskSettings.unitSystem, compact: true)
            } ?? "—"
            renderer = TextRenderer(text: free, reservedText: moduleSettings.usesFixedWidth ? "999GiB" : nil)
        case "rates":
            let read = DiskValueFormatter.rate(
                rates.read,
                unitSystem: diskSettings.unitSystem,
                compact: true
            )
            let write = DiskValueFormatter.rate(
                rates.write,
                unitSystem: diskSettings.unitSystem,
                compact: true
            )
            renderer = NetworkRateStackRenderer(
                download: sample == nil ? "—" : read,
                upload: sample == nil ? "—" : write,
                reservedValue: diskSettings.unitSystem == .binary ? "999GiB/s" : "999GB/s"
            )
        default:
            let graph = graphValues(history)
            renderer = DiskActivityGraphRenderer(
                reads: graph.reads,
                writes: graph.writes,
                style: moduleSettings.graphStyle
            )
        }

        guard sample != nil else {
            return StatusItemContent(image: renderer.render(in: context), accessibilityValue: "Disks unavailable")
        }

        let read = DiskValueFormatter.rate(rates.read, unitSystem: diskSettings.unitSystem)
        let write = DiskValueFormatter.rate(rates.write, unitSystem: diskSettings.unitSystem)
        let volumeDescription = volume.map { selectedVolume in
            let free = DiskValueFormatter.capacity(
                selectedVolume.availableBytes,
                unitSystem: diskSettings.unitSystem
            )
            return ", \(selectedVolume.name) \(free) free"
        } ?? ""
        return StatusItemContent(
            image: renderer.render(in: context),
            accessibilityValue: "Disks read \(read), write \(write)\(volumeDescription)"
        )
    }

    private static func aggregateRates(_ sample: DiskSample) -> (read: Double, write: Double) {
        sample.devices.reduce(into: (read: 0.0, write: 0.0)) { result, device in
            result.read += device.readBytesPerSecond
            result.write += device.writeBytesPerSecond
        }
    }

    private static func freePercent(_ volume: DiskVolumeSample) -> Double {
        volume.totalBytes > 0 ? Double(volume.availableBytes) / Double(volume.totalBytes) * 100 : 0
    }

    private static func graphValues(
        _ history: [HistoryEntry<DiskSample.GraphValue>]
    ) -> (reads: [Double], writes: [Double]) {
        let rates = history.map { $0.value }
        let maximum = max(1, rates.reduce(0) { max($0, $1.read, $1.write) } * 1.1)
        return (
            reads: rates.map { min(1, max(0, $0.read / maximum)) },
            writes: rates.map { min(1, max(0, $0.write / maximum)) }
        )
    }
}
