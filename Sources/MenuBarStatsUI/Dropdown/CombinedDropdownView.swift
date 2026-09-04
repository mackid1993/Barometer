import MenuBarStatsCore
import SwiftUI

/// Tabbed current-value dashboard for the modules one stack draws from.
public struct CombinedDropdownView: View {
    /// Fixed hosted content width; height follows the content.
    public static let contentSize = CGSize(width: 380, height: 440)

    private let stackID: Int
    private let cpuStore: ModuleStore<CPUSample>
    private let memoryStore: ModuleStore<MemorySample>
    private let gpuStore: ModuleStore<GPUSample>
    private let networkStore: ModuleStore<NetworkSample>
    private let diskStore: ModuleStore<DiskSample>
    private let sensorStore: ModuleStore<SensorSample>
    private let batteryStore: ModuleStore<BatterySample>
    private let weatherStore: ModuleStore<WeatherSample>
    private let timeStore: ModuleStore<TimeSample>
    private let settingsStore: SettingsStore
    @State private var selection: ModuleID = .cpu

    /// Creates a stack dropdown over existing module stores.
    public init(
        stackID: Int,
        cpuStore: ModuleStore<CPUSample>,
        memoryStore: ModuleStore<MemorySample>,
        gpuStore: ModuleStore<GPUSample>,
        networkStore: ModuleStore<NetworkSample>,
        diskStore: ModuleStore<DiskSample>,
        sensorStore: ModuleStore<SensorSample>,
        batteryStore: ModuleStore<BatterySample>,
        weatherStore: ModuleStore<WeatherSample>,
        timeStore: ModuleStore<TimeSample>,
        settingsStore: SettingsStore
    ) {
        self.stackID = stackID
        self.cpuStore = cpuStore
        self.memoryStore = memoryStore
        self.gpuStore = gpuStore
        self.networkStore = networkStore
        self.diskStore = diskStore
        self.sensorStore = sensorStore
        self.batteryStore = batteryStore
        self.weatherStore = weatherStore
        self.timeStore = timeStore
        self.settingsStore = settingsStore
    }

    /// The name the person who created this stack gave it.
    private var stackName: String {
        settingsStore.settings.stacks.stack(id: stackID)?.displayName ?? "Stack"
    }

    /// Source modules of the stack's metrics, in metric order and without repeats.
    private var members: [ModuleID] {
        guard let stack = settingsStore.settings.stacks.stack(id: stackID) else {
            return []
        }
        var seen: Set<ModuleID> = []
        return stack.metrics.map(\.module).filter { seen.insert($0).inserted }
    }

    public var body: some View {
        let members = members
        let stack = settingsStore.settings.stacks.stack(id: stackID)
        let selected = members.contains(selection) ? selection : members.first
        let accent = ModuleAccent.resolve(settingsStore.settings, module: .combined)
        let selectedAccent = selected.map { ModuleAccent.resolve(settingsStore.settings, module: $0) } ?? accent

        DropdownScaffold(size: Self.contentSize) {
            HStack(spacing: 12) {
                IconTile(symbolName: "rectangle.3.group.fill", accent: accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stackName).font(BarometerDesign.titleFont)
                    Text("\(stack?.metrics.count ?? 0) readings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 2)

            if let selected {
                CapsulePicker(
                    options: members,
                    selection: selectionBinding(fallback: selected),
                    label: \.displayName,
                    accent: selectedAccent
                )
                GlassCard(tint: selectedAccent.primary) {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(selected.displayName) {
                            Image(systemName: selected.symbolName)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(selectedAccent.primary)
                        }
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(metrics(for: selected), id: \.label) { metric in
                                StatTile(
                                    symbol: metric.symbol, label: metric.label, value: metric.value,
                                    tint: selectedAccent.primary)
                            }
                        }
                    }
                }
            } else {
                GlassCard {
                    ContentUnavailableView(
                        "No readings",
                        systemImage: "rectangle.3.group",
                        description: Text("Add readings in Stacks settings.")
                    )
                }
            }
        }
    }

    private struct Metric {
        let symbol: String
        let label: String
        let value: String
    }

    private func selectionBinding(fallback: ModuleID) -> Binding<ModuleID> {
        Binding(
            get: { members.contains(selection) ? selection : fallback },
            set: { selection = $0 })
    }

    private func metrics(for module: ModuleID) -> [Metric] {
        switch module {
        case .cpu:
            return [
                Metric(
                    symbol: "cpu", label: "Utilization",
                    value: cpuStore.latestSample.map { String(format: "%.1f%%", $0.totalPercent) } ?? "—"),
                Metric(
                    symbol: "gauge.with.dots.needle.33percent", label: "Load average",
                    value: cpuStore.latestSample.map {
                        $0.loadAverages.prefix(1).map { String(format: "%.2f", $0) }.joined()
                    } ?? "—"),
            ]
        case .gpu:
            return [
                Metric(
                    symbol: "square.stack.3d.up", label: "Utilization",
                    value: gpuStore.latestSample.map {
                        String(format: "%.1f%%", $0.deviceUtilizationPercent)
                    } ?? "—"),
                Metric(
                    symbol: "memorychip", label: "Memory in use",
                    value: gpuStore.latestSample?.memoryInUseBytes.map {
                        String(format: "%.2f GiB", Double($0) / 1_073_741_824)
                    } ?? "—"),
            ]
        case .memory:
            return [
                Metric(
                    symbol: "memorychip", label: "Used",
                    value: memoryStore.latestSample.map { sample in
                        guard sample.total > 0 else { return "—" }
                        return String(format: "%.1f%%", Double(sample.used) / Double(sample.total) * 100)
                    } ?? "—"),
                Metric(
                    symbol: "gauge.with.needle", label: "Pressure",
                    value: memoryStore.latestSample.map { String(format: "%.0f%%", $0.pressurePercent) } ?? "—"),
            ]
        case .network:
            return [
                Metric(
                    symbol: "arrow.down.circle", label: "Download",
                    value: networkStore.latestSample?.primary.map {
                        ByteCountFormatter.string(fromByteCount: Int64($0.downloadBytesPerSecond), countStyle: .decimal)
                            + "/s"
                    } ?? "—"),
                Metric(
                    symbol: "arrow.up.circle", label: "Upload",
                    value: networkStore.latestSample?.primary.map {
                        ByteCountFormatter.string(fromByteCount: Int64($0.uploadBytesPerSecond), countStyle: .decimal)
                            + "/s"
                    } ?? "—"),
            ]
        case .disks:
            return [
                Metric(
                    symbol: "internaldrive", label: "Mounted volumes",
                    value: diskStore.latestSample.map { "\($0.volumes.count)" } ?? "—"),
                Metric(
                    symbol: "externaldrive", label: "Active devices",
                    value: diskStore.latestSample.map { "\($0.devices.count)" } ?? "—"),
            ]
        case .sensors:
            return (sensorStore.latestSample?.readings.prefix(6).map { $0 } ?? []).map { reading in
                Metric(
                    symbol: "thermometer.medium", label: reading.name,
                    value: String(format: "%.1f %@", reading.value, reading.unit.rawValue))
            }
        case .battery:
            return [
                Metric(
                    symbol: "battery.75percent", label: "Charge",
                    value: batteryStore.latestSample.map { String(format: "%.1f%%", $0.chargePercent) } ?? "—"),
                Metric(
                    symbol: "bolt.fill", label: "State",
                    value: batteryStore.latestSample.map { $0.state.rawValue } ?? "—"),
            ]
        case .weather:
            return [
                Metric(
                    symbol: "thermometer.sun", label: "Temperature",
                    value: weatherStore.latestSample.map {
                        let forecast = $0.forecast
                        return String(format: "%.0f%@", forecast.current.temperature, forecast.units.temperature.symbol)
                    } ?? "—"),
                Metric(
                    symbol: "cloud.sun", label: "Conditions",
                    value: weatherStore.latestSample.map { $0.forecast.current.code.description } ?? "—"),
            ]
        case .time:
            return [
                Metric(
                    symbol: "clock", label: "Local time",
                    value: timeStore.latestSample.map {
                        TimeFormatEngine.render(
                            date: $0.timestamp,
                            timeZone: TimeZone(identifier: $0.systemTimeZoneIdentifier) ?? .current,
                            template: settingsStore.settings.time.menuBarTemplate,
                            showsSeconds: settingsStore.settings.time.showsSeconds
                        )
                    } ?? "—")
            ]
        case .combined:
            return []
        }
    }
}
