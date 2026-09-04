import AppKit
import Darwin
import MenuBarStatsCore
import SwiftUI
import SystemSources

enum HistoryRange: String, CaseIterable, Identifiable {
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

// MARK: - CPU

/// Live CPU details shown inside the CPU status-item menu.
public struct CPUDropdownView: View {
    /// Fixed hosted content size for the menu item.
    public static let contentSize = CGSize(width: 380, height: 500)

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
        let accent = ModuleAccent.resolve(settingsStore.settings, module: .cpu)

        DropdownScaffold(size: Self.contentSize) {
            HeroHeader(
                symbolName: "cpu",
                title: "CPU",
                subtitle: sample.map(Self.subtitle) ?? "Waiting for the first sample",
                value: sample.map { String(format: "%.1f%%", $0.totalPercent) } ?? "—",
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
                    AreaGraph(values: values, accent: accent)
                        .frame(height: 84)
                    if let sample {
                        HStack(spacing: 6) {
                            Chip(text: String(format: "User %.0f%%", sample.userPercent), color: accent.primary)
                            Chip(text: String(format: "System %.0f%%", sample.systemPercent), color: accent.secondary)
                            Chip(text: String(format: "Idle %.0f%%", sample.idlePercent), color: .secondary)
                        }
                    }
                }
            }

            if let sample {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Cores") {
                            Text(Self.coreSummary(sample))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], spacing: 8) {
                            ForEach(sample.perCore, id: \.index) { core in
                                CoreBar(core: core, accent: accent)
                            }
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 2) {
                        SectionLabel("System")
                        MetricRow(
                            label: "Load average",
                            value: sample.loadAverages.map { String(format: "%.2f", $0) }.joined(separator: "  ·  "),
                            symbol: "gauge.with.dots.needle.33percent",
                            tint: accent.primary
                        )
                        MetricRow(
                            label: "Uptime", value: Self.uptime(sample.uptime), symbol: "clock", tint: accent.primary)
                        MetricRow(
                            label: "Processes",
                            value: "\(sample.processCount)  ·  \(sample.threadCount) threads",
                            symbol: "square.stack.3d.up",
                            tint: accent.primary
                        )
                    }
                }

                if settings.showsProcesses, !sample.topProcesses.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 2) {
                            SectionLabel("Top processes")
                            ForEach(sample.topProcesses.prefix(settings.processCount), id: \.processIdentifier) {
                                process in
                                CPUProcessRow(process: process, accent: accent)
                            }
                        }
                    }
                }
            }
        }
    }

    private static func subtitle(_ sample: CPUSample) -> String {
        String(
            format: "%.0f%% user  ·  %.0f%% system  ·  %.0f%% idle", sample.userPercent, sample.systemPercent,
            sample.idlePercent)
    }

    private static func coreSummary(_ sample: CPUSample) -> String {
        let performance = sample.perCore.filter { $0.kind == .performance }.count
        let efficiency = sample.perCore.count - performance
        guard efficiency > 0 else {
            return "\(sample.perCore.count) cores"
        }
        return "\(performance) performance · \(efficiency) efficiency"
    }

    private static func uptime(_ interval: TimeInterval?) -> String {
        guard let interval else { return "Unavailable" }
        let days = Int(interval) / 86_400
        let hours = Int(interval) % 86_400 / 3_600
        let minutes = Int(interval) % 3_600 / 60
        return days > 0 ? "\(days)d \(hours)h \(minutes)m" : "\(hours)h \(minutes)m"
    }
}

private struct CoreBar: View {
    let core: CPUCoreSample
    let accent: ModuleAccent

    var body: some View {
        let isPerformance = core.kind == .performance
        let gradient =
            isPerformance
            ? accent.horizontalGradient
            : LinearGradient(
                colors: [accent.secondary, Color(hex: 0x6EE7B7)], startPoint: .leading, endPoint: .trailing)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                Text(isPerformance ? "P\(core.index + 1)" : "E\(core.index + 1)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", core.usagePercent))
                    .font(.caption2.monospacedDigit())
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.3), value: core.usagePercent)
            }
            CapsuleBar(
                fraction: core.usagePercent / 100,
                gradient: gradient,
                height: 5,
                glowColor: isPerformance ? accent.primary : accent.secondary
            )
        }
    }
}

private struct CPUProcessRow: View {
    let process: CPUProcessSample
    let accent: ModuleAccent

    var body: some View {
        ProcessRow(
            icon: ProcessIconResolver.image(processIdentifier: process.processIdentifier, path: process.path),
            name: process.name,
            detail: String(format: "%.1f%%", process.cpuPercent),
            fraction: min(1, process.cpuPercent / 100),
            accent: accent
        ) {
            Button(action: terminate) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Quit process")
        }
    }

    private func terminate() {
        if process.userIdentifier != UInt32(getuid()) {
            let alert = NSAlert()
            alert.messageText = "Quit \(process.name)?"
            alert.informativeText =
                "This process belongs to another user or to macOS. "
                + "Quitting it may affect the system."
            alert.addButton(withTitle: "Quit Process")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        _ = Darwin.kill(process.processIdentifier, SIGTERM)
    }
}

// MARK: - Memory

/// Live memory details shown inside the Memory status-item menu.
public struct MemoryDropdownView: View {
    /// Fixed hosted content size for the menu item.
    public static let contentSize = CGSize(width: 380, height: 450)

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
        let accent = ModuleAccent.resolve(settingsStore.settings, module: .memory)

        DropdownScaffold(size: Self.contentSize) {
            HeroHeader(
                symbolName: "memorychip",
                title: "Memory",
                subtitle: sample.map(Self.usedText) ?? "Waiting for the first sample",
                value: sample.map { Self.usedPercent($0) } ?? "—",
                accent: accent
            )

            if let sample {
                GlassCard(tint: accent.primary) {
                    VStack(alignment: .leading, spacing: 9) {
                        SectionLabel("Breakdown") {
                            Text("\(Self.bytes(sample.free)) free")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .contentTransition(.numericText())
                        }
                        MemoryBreakdownBar(sample: sample, accent: accent)
                            .frame(height: 12)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                            Chip(text: "App \(Self.bytes(sample.app))", color: accent.primary)
                            Chip(text: "Wired \(Self.bytes(sample.wired))", color: accent.secondary)
                            Chip(text: "Compressed \(Self.bytes(sample.compressed))", color: .orange)
                            Chip(text: "Cached \(Self.bytes(sample.cached))", color: .secondary)
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Pressure") {
                            Chip(
                                text: Self.pressureName(sample.pressureLevel),
                                color: pressureColor(
                                    sample.pressurePercent, settings: settingsStore.settings, accent: accent),
                                symbol: Self.pressureSymbol(sample.pressureLevel)
                            )
                        }
                        AreaGraph(
                            values: values,
                            accent: ModuleAccent(
                                primary: pressureColor(
                                    sample.pressurePercent, settings: settingsStore.settings, accent: accent),
                                secondary: accent.secondary
                            )
                        )
                        .frame(height: 72)
                        MetricRow(
                            label: "Memory pressure",
                            value: String(format: "%.0f%%", sample.pressurePercent),
                            symbol: "gauge.with.needle",
                            tint: accent.primary
                        )
                        MetricRow(
                            label: "Swap",
                            value: "\(Self.bytes(sample.swapUsed)) of \(Self.bytes(sample.swapTotal))",
                            symbol: "arrow.left.arrow.right",
                            tint: accent.primary
                        )
                    }
                }

                if settings.showsProcesses, !sample.topProcesses.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 2) {
                            SectionLabel("Top processes")
                            ForEach(sample.topProcesses.prefix(settings.processCount), id: \.processIdentifier) {
                                process in
                                ProcessRow(
                                    icon: ProcessIconResolver.image(
                                        processIdentifier: process.processIdentifier,
                                        path: process.path
                                    ),
                                    name: process.name,
                                    detail: Self.bytes(process.physicalFootprint),
                                    fraction: sample.total > 0
                                        ? Double(process.physicalFootprint) / Double(sample.total)
                                        : nil,
                                    accent: accent
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private static func usedText(_ sample: MemorySample) -> String {
        "\(bytes(sample.used)) of \(bytes(sample.total)) used"
    }

    private static func usedPercent(_ sample: MemorySample) -> String {
        guard sample.total > 0 else { return "—" }
        return String(format: "%.0f%%", Double(sample.used) / Double(sample.total) * 100)
    }

    fileprivate static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory)
    }

    private static func pressureName(_ level: MemoryPressureLevel) -> String {
        switch level {
        case .normal: "Normal"
        case .warning: "Warning"
        case .critical: "Critical"
        case .unavailable: "Unknown"
        }
    }

    private static func pressureSymbol(_ level: MemoryPressureLevel) -> String {
        switch level {
        case .normal: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "exclamationmark.octagon.fill"
        case .unavailable: "questionmark.circle"
        }
    }

    private func pressureColor(_ pressure: Double, settings: AppSettings, accent: ModuleAccent) -> Color {
        if pressure >= 80 {
            return AppearanceColorResolver.critical(settings, module: .memory)
        }
        if pressure >= 60 {
            return AppearanceColorResolver.warning(settings, module: .memory)
        }
        return accent.primary
    }
}

private struct MemoryBreakdownBar: View {
    let sample: MemorySample
    let accent: ModuleAccent

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 1) {
                segment(sample.app, color: accent.primary, width: geometry.size.width)
                segment(sample.wired, color: accent.secondary, width: geometry.size.width)
                segment(sample.compressed, color: .orange, width: geometry.size.width)
                segment(sample.cached, color: .secondary.opacity(0.55), width: geometry.size.width)
                segment(sample.free, color: .primary.opacity(0.08), width: geometry.size.width)
            }
            .clipShape(Capsule())
        }
        .animation(.snappy(duration: 0.35), value: sample.used)
    }

    private func segment(_ amount: UInt64, color: Color, width: CGFloat) -> some View {
        color.frame(width: sample.total > 0 ? width * CGFloat(amount) / CGFloat(sample.total) : 0)
    }
}

// MARK: - Shared process helpers

struct ProcessIcon: View {
    let processIdentifier: pid_t
    let path: String?

    var body: some View {
        Image(nsImage: ProcessIconResolver.image(processIdentifier: processIdentifier, path: path))
            .resizable()
            .interpolation(.high)
            .frame(width: 16, height: 16)
    }
}

@MainActor
enum ProcessIconResolver {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(processIdentifier: pid_t, path: String?) -> NSImage {
        let cacheKey = "\(processIdentifier):\(path ?? "")" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let image =
            applicationURL(for: path).map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSRunningApplication(processIdentifier: processIdentifier)?.icon
            ?? path.map { NSWorkspace.shared.icon(forFile: $0) }
            ?? NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: "Command-line process")
            ?? NSImage()
        cache.setObject(image, forKey: cacheKey)
        return image
    }

    static func applicationURL(for path: String?) -> URL? {
        guard let path else {
            return nil
        }
        var candidate = URL(fileURLWithPath: path).deletingLastPathComponent()
        var outermostApplication: URL?
        while candidate.path != "/" {
            if candidate.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
                outermostApplication = candidate
            }
            candidate.deleteLastPathComponent()
        }
        return outermostApplication
    }
}
