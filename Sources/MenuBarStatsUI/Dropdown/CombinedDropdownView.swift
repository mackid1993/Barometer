import MenuBarStatsCore
import SwiftUI

/// Tabbed current-value dashboard for modules included in Combined.
public struct CombinedDropdownView: View {
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

    /// Creates a Combined dropdown over existing module stores.
    public init(
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

    public var body: some View {
        let members = settingsStore.settings.combined.members
        let selected = members.contains(selection) ? selection : members.first
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Combined").font(.headline)
                Spacer()
                if let selected {
                    Picker("Module", selection: selectionBinding(fallback: selected)) {
                        ForEach(members, id: \.self) { module in Text(module.displayName).tag(module) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 190)
                }
            }
            Divider()
            if let selected {
                summary(for: selected)
            } else {
                ContentUnavailableView(
                    "No included modules",
                    systemImage: "rectangle.3.group",
                    description: Text("Add modules in Combined settings.")
                )
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 400, height: 420)
    }

    private func selectionBinding(fallback: ModuleID) -> Binding<ModuleID> {
        Binding(get: { settingsStore.settings.combined.members.contains(selection) ? selection : fallback },
                set: { selection = $0 })
    }

    @ViewBuilder
    private func summary(for module: ModuleID) -> some View {
        switch module {
        case .cpu:
            metric("CPU utilization", cpuStore.latestSample.map { String(format: "%.1f%%", $0.totalPercent) })
        case .gpu:
            metric("GPU utilization", gpuStore.latestSample.map {
                String(format: "%.1f%%", $0.deviceUtilizationPercent)
            })
        case .memory:
            metric("Memory used", memoryStore.latestSample.map { sample in
                guard sample.total > 0 else { return "Unavailable" }
                return String(format: "%.1f%%", Double(sample.used) / Double(sample.total) * 100)
            })
        case .network:
            metric("Download", networkStore.latestSample?.primary.map {
                ByteCountFormatter.string(fromByteCount: Int64($0.downloadBytesPerSecond), countStyle: .decimal) + "/s"
            })
            metric("Upload", networkStore.latestSample?.primary.map {
                ByteCountFormatter.string(fromByteCount: Int64($0.uploadBytesPerSecond), countStyle: .decimal) + "/s"
            })
        case .disks:
            metric("Mounted volumes", diskStore.latestSample.map { "\($0.volumes.count)" })
            metric("Active devices", diskStore.latestSample.map { "\($0.devices.count)" })
        case .sensors:
            ForEach(sensorStore.latestSample?.readings.prefix(8).map { $0 } ?? [], id: \.id) { reading in
                metric(reading.name, String(format: "%.1f %@", reading.value, reading.unit.rawValue))
            }
        case .battery:
            metric("Battery", batteryStore.latestSample.map { String(format: "%.1f%%", $0.chargePercent) })
            metric("State", batteryStore.latestSample.map { $0.state.rawValue })
        case .weather:
            metric("Temperature", weatherStore.latestSample.map {
                let forecast = $0.forecast
                return String(format: "%.0f%@", forecast.current.temperature, forecast.units.temperature.symbol)
            })
            metric("Conditions", weatherStore.latestSample.map { $0.forecast.current.code.description })
        case .time:
            metric("Local time", timeStore.latestSample.map {
                TimeFormatEngine.render(
                    date: $0.timestamp,
                    timeZone: TimeZone(identifier: $0.systemTimeZoneIdentifier) ?? .current,
                    template: settingsStore.settings.time.menuBarTemplate,
                    showsSeconds: settingsStore.settings.time.showsSeconds
                )
            })
        case .combined:
            EmptyView()
        }
    }

    private func metric(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value ?? "Unavailable").monospacedDigit().lineLimit(1)
        }
        .font(.subheadline)
    }
}
