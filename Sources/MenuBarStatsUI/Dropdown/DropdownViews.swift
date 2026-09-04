import AppKit
import Darwin
import MenuBarStatsCore
import SwiftUI

private enum HistoryRange: String, CaseIterable, Identifiable {
    case oneMinute = "1m"
    case fiveMinutes = "5m"
    case thirtyMinutes = "30m"
    case threeHours = "3h"
    case twentyFourHours = "24h"

    var id: Self { self }

    var duration: TimeInterval {
        switch self {
        case .oneMinute: 60
        case .fiveMinutes: 300
        case .thirtyMinutes: 1_800
        case .threeHours: 10_800
        case .twentyFourHours: 86_400
        }
    }
}

/// Live CPU details shown inside the CPU status-item menu.
public struct CPUDropdownView: View {
    private let store: ModuleStore<CPUSample>
    private let settingsStore: SettingsStore
    @State private var range: HistoryRange = .fiveMinutes

    /// Creates a CPU dropdown backed by the supplied observable store.
    public init(store: ModuleStore<CPUSample>, settingsStore: SettingsStore) {
        self.store = store
        self.settingsStore = settingsStore
    }

    public var body: some View {
        let sample = store.latestSample
        let cutoff = Date().addingTimeInterval(-range.duration)
        let values = store.history.entries
            .filter { $0.timestamp >= cutoff }
            .map { $0.value.totalPercent / 100 }
        let _ = store.revision
        let settings = settingsStore.settings.modules[.cpu] ?? ModuleSettings()

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("CPU").font(.headline)
                    Spacer()
                    Text(sample.map { String(format: "%.1f%%", $0.totalPercent) } ?? "Unavailable")
                        .font(.system(.headline, design: .rounded).monospacedDigit())
                }

                HStack {
                    Text("History").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Picker("Range", selection: $range) {
                        ForEach(HistoryRange.allCases) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                }
                HistoryGraph(values: values, color: .cyan)
                    .frame(height: 72)

                if let sample {
                    Text("CORES").sectionLabel()
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 8)], spacing: 7) {
                        ForEach(sample.perCore, id: \.index) { core in
                            CoreBar(core: core)
                        }
                    }

                    Divider()
                    MetricRow(label: "Load Average", value: sample.loadAverages.map {
                        String(format: "%.2f", $0)
                    }.joined(separator: "  "))
                    MetricRow(label: "Uptime", value: Self.uptime(sample.uptime))
                    MetricRow(label: "Processes", value: "\(sample.processCount)  ·  \(sample.threadCount) threads")

                    if settings.showsProcesses, !sample.topProcesses.isEmpty {
                        Text("TOP PROCESSES").sectionLabel()
                        ForEach(sample.topProcesses.prefix(settings.processCount), id: \.processIdentifier) { process in
                            CPUProcessRow(process: process)
                        }
                    }
                }
            }
            .padding(14)
        }
        .frame(width: 320, height: 438)
    }

    private static func uptime(_ interval: TimeInterval?) -> String {
        guard let interval else { return "Unavailable" }
        let days = Int(interval) / 86_400
        let hours = Int(interval) % 86_400 / 3_600
        let minutes = Int(interval) % 3_600 / 60
        return days > 0 ? "\(days)d \(hours)h \(minutes)m" : "\(hours)h \(minutes)m"
    }
}

/// Live memory details shown inside the Memory status-item menu.
public struct MemoryDropdownView: View {
    private let store: ModuleStore<MemorySample>
    private let settingsStore: SettingsStore

    /// Creates a Memory dropdown backed by the supplied observable store.
    public init(store: ModuleStore<MemorySample>, settingsStore: SettingsStore) {
        self.store = store
        self.settingsStore = settingsStore
    }

    public var body: some View {
        let sample = store.latestSample
        let values = store.history.entries.map { $0.value.pressurePercent / 100 }
        let _ = store.revision
        let settings = settingsStore.settings.modules[.memory] ?? ModuleSettings()

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Memory").font(.headline)
                    Spacer()
                    Text(sample.map(Self.usedText) ?? "Unavailable")
                        .font(.system(.headline, design: .rounded).monospacedDigit())
                }

                if let sample {
                    MemoryBreakdownBar(sample: sample).frame(height: 12)
                    HStack(spacing: 10) {
                        LegendDot(color: .blue, label: "App \(Self.bytes(sample.app))")
                        LegendDot(color: .purple, label: "Wired \(Self.bytes(sample.wired))")
                    }
                    HStack(spacing: 10) {
                        LegendDot(color: .orange, label: "Compressed \(Self.bytes(sample.compressed))")
                        LegendDot(color: .gray, label: "Cached \(Self.bytes(sample.cached))")
                    }

                    Text("PRESSURE").sectionLabel()
                    HistoryGraph(values: values, color: Self.pressureColor(sample.pressurePercent))
                        .frame(height: 72)
                    MetricRow(
                        label: "Memory Pressure",
                        value: String(format: "%.0f%%", sample.pressurePercent)
                    )
                    MetricRow(label: "Swap", value: "\(Self.bytes(sample.swapUsed)) of \(Self.bytes(sample.swapTotal))")

                    if settings.showsProcesses, !sample.topProcesses.isEmpty {
                        Text("TOP PROCESSES").sectionLabel()
                        ForEach(sample.topProcesses.prefix(settings.processCount), id: \.processIdentifier) { process in
                            MemoryProcessRow(process: process)
                        }
                    }
                }
            }
            .padding(14)
        }
        .frame(width: 320, height: 386)
    }

    private static func usedText(_ sample: MemorySample) -> String {
        "\(bytes(sample.used)) / \(bytes(sample.total))"
    }

    fileprivate static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory)
    }

    private static func pressureColor(_ pressure: Double) -> Color {
        pressure >= 80 ? .red : pressure >= 60 ? .orange : .green
    }
}

private struct HistoryGraph: View {
    let values: [Double]
    let color: Color

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            var path = Path()
            for (index, rawValue) in values.enumerated() {
                let fraction = CGFloat(index) / CGFloat(values.count - 1)
                let value = CGFloat(min(max(rawValue, 0), 1))
                let point = CGPoint(x: fraction * size.width, y: (1 - value) * size.height)
                index == 0 ? path.move(to: point) : path.addLine(to: point)
            }
            context.stroke(path, with: .color(color), lineWidth: 1.75)
        }
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct CoreBar: View {
    let core: CPUCoreSample

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Text("C\(core.index + 1)").font(.caption2)
                Spacer()
                Text(String(format: "%.0f%%", core.usagePercent)).font(.caption2.monospacedDigit())
            }
            ProgressView(value: core.usagePercent, total: 100)
                .progressViewStyle(.linear)
                .tint(core.kind == .performance ? .cyan : .mint)
        }
    }
}

private struct CPUProcessRow: View {
    let process: CPUProcessSample

    var body: some View {
        HStack(spacing: 7) {
            ProcessIcon(path: process.path)
            Text(process.name).lineLimit(1)
            Spacer()
            Text(String(format: "%.1f%%", process.cpuPercent)).monospacedDigit().foregroundStyle(.secondary)
            Button(action: terminate) {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.plain)
            .help("Quit process")
        }
        .font(.caption)
    }

    private func terminate() {
        if process.userIdentifier != UInt32(getuid()) {
            let alert = NSAlert()
            alert.messageText = "Quit \(process.name)?"
            alert.informativeText = "This process belongs to another user or to macOS. "
                + "Quitting it may affect the system."
            alert.addButton(withTitle: "Quit Process")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        _ = Darwin.kill(process.processIdentifier, SIGTERM)
    }
}

private struct MemoryProcessRow: View {
    let process: MemoryProcessSample

    var body: some View {
        HStack(spacing: 7) {
            ProcessIcon(path: process.path)
            Text(process.name).lineLimit(1)
            Spacer()
            Text(MemoryDropdownView.bytes(process.physicalFootprint))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}

private struct ProcessIcon: View {
    let path: String?

    var body: some View {
        Image(nsImage: path.map { NSWorkspace.shared.icon(forFile: $0) } ?? NSImage())
            .resizable()
            .frame(width: 16, height: 16)
    }
}

private struct MemoryBreakdownBar: View {
    let sample: MemorySample

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                segment(sample.app, color: .blue, width: geometry.size.width)
                segment(sample.wired, color: .purple, width: geometry.size.width)
                segment(sample.compressed, color: .orange, width: geometry.size.width)
                segment(sample.cached, color: .gray, width: geometry.size.width)
                segment(sample.free, color: .secondary.opacity(0.22), width: geometry.size.width)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    private func segment(_ amount: UInt64, color: Color, width: CGFloat) -> some View {
        color.frame(width: sample.total > 0 ? width * CGFloat(amount) / CGFloat(sample.total) : 0)
    }
}

private struct LegendDot: View {
    let color: Color
    let label: String

    var body: some View {
        Label {
            Text(label).lineLimit(1)
        } icon: {
            Circle().fill(color).frame(width: 7, height: 7)
        }
        .font(.caption2)
    }
}

private struct MetricRow: View {
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
    func sectionLabel() -> some View {
        font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
    }
}
