import MenuBarStatsCore
import SwiftUI

/// Tabbed dropdown for a stack, hosting each source module's own full dropdown.
///
/// A stack draws readings from several modules, and someone opening it wants the same detail they
/// would get from those modules individually, not a summary of it. Each tab therefore embeds the
/// module's real dropdown view. Those views bring their own scroll container, so this one adds only
/// the tab strip above them rather than nesting a second scaffold.
public struct CombinedDropdownView: View {
    /// Fixed hosted content width; height follows the selected tab's content.
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
    private let locationAccess: @MainActor () -> LocationAccessState
    private let locationAction: @MainActor () -> Void
    private let weatherRefreshAction: @MainActor () -> Void
    private let resetEnergyAction: @MainActor () -> Void
    private let requestCalendarAccess: @MainActor () -> Void
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
        settingsStore: SettingsStore,
        locationAccess: @escaping @MainActor () -> LocationAccessState,
        locationAction: @escaping @MainActor () -> Void,
        weatherRefreshAction: @escaping @MainActor () -> Void,
        resetEnergyAction: @escaping @MainActor () -> Void,
        requestCalendarAccess: @escaping @MainActor () -> Void
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
        self.locationAccess = locationAccess
        self.locationAction = locationAction
        self.weatherRefreshAction = weatherRefreshAction
        self.resetEnergyAction = resetEnergyAction
        self.requestCalendarAccess = requestCalendarAccess
    }

    /// The name the person who created this stack gave it.
    private var stackName: String {
        settingsStore.settings.stacks.stack(id: stackID)?.displayName ?? "Stack"
    }

    /// Source modules of the stack's readings, in reading order and without repeats.
    private var members: [ModuleID] {
        guard let stack = settingsStore.settings.stacks.stack(id: stackID) else {
            return []
        }
        var seen: Set<ModuleID> = []
        return stack.metrics.map(\.module).filter { seen.insert($0).inserted }
    }

    public var body: some View {
        let members = members
        let selected = members.contains(selection) ? selection : members.first
        let accent = ModuleAccent.resolve(settingsStore.settings, module: .combined)

        VStack(alignment: .leading, spacing: 0) {
            if let selected {
                if members.count > 1 {
                    CapsulePicker(
                        options: members,
                        selection: selectionBinding(fallback: selected),
                        label: \.displayName,
                        accent: ModuleAccent.resolve(settingsStore.settings, module: selected)
                    )
                    .padding(.horizontal, BarometerDesign.panelPadding)
                    .padding(.top, BarometerDesign.panelPadding)
                    .padding(.bottom, 4)
                }
                // The module's own dropdown, complete, including its scroll container.
                moduleDropdown(selected)
            } else {
                DropdownScaffold(size: Self.contentSize) {
                    HStack(spacing: 12) {
                        IconTile(symbolName: "rectangle.3.group.fill", accent: accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stackName).font(BarometerDesign.titleFont)
                            Text("No readings").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 2)

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
        .frame(width: Self.contentSize.width)
    }

    @ViewBuilder
    private func moduleDropdown(_ module: ModuleID) -> some View {
        switch module {
        case .cpu:
            CPUDropdownView(store: cpuStore, settingsStore: settingsStore)
        case .memory:
            MemoryDropdownView(store: memoryStore, settingsStore: settingsStore)
        case .gpu:
            GPUDropdownView(store: gpuStore, settingsStore: settingsStore)
        case .disks:
            DiskDropdownView(store: diskStore, settingsStore: settingsStore)
        case .network:
            NetworkDropdownView(
                store: networkStore,
                settingsStore: settingsStore,
                locationAccess: locationAccess,
                locationAction: locationAction
            )
        case .sensors:
            SensorsDropdownView(
                store: sensorStore,
                settingsStore: settingsStore,
                resetEnergyAction: resetEnergyAction
            )
        case .battery:
            BatteryDropdownView(store: batteryStore, settingsStore: settingsStore)
        case .weather:
            WeatherDropdownView(
                store: weatherStore,
                settingsStore: settingsStore,
                refreshAction: weatherRefreshAction
            )
        case .time:
            TimeDropdownView(
                store: timeStore,
                weatherStore: weatherStore,
                settingsStore: settingsStore,
                requestCalendarAccess: requestCalendarAccess
            )
        case .combined:
            EmptyView()
        }
    }

    private func selectionBinding(fallback: ModuleID) -> Binding<ModuleID> {
        Binding(
            get: { members.contains(selection) ? selection : fallback },
            set: { selection = $0 }
        )
    }
}
