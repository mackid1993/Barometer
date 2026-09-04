import AppKit
import MenuBarStatsCore
import Observation
import SwiftUI

/// Wires Phase 1 monitors, stores, schedulers, and status item controllers together.
@MainActor
public final class MonitoringCoordinator {
    /// Observable CPU state used by status items and dropdowns.
    public let cpuStore = ModuleStore<CPUSample>(historyCapacity: 86_400)

    /// Observable Memory state used by status items and dropdowns.
    public let memoryStore = ModuleStore<MemorySample>(historyCapacity: 43_200)

    /// Shared application settings.
    public let settingsStore: SettingsStore

    private let cpuScheduler: Scheduler<CPUMonitor>
    private let memoryScheduler: Scheduler<MemoryMonitor>
    private let powerStateObserver = PowerStateObserver()
    private let displaySleepWatcher = DisplaySleepWatcher()
    private var cpuController: StatusItemController<CPUSample>?
    private var memoryController: StatusItemController<MemorySample>?
    private var cpuDropdown: DropdownController?
    private var memoryDropdown: DropdownController?
    private var cpuSampleTask: Task<Void, Never>?
    private var memorySampleTask: Task<Void, Never>?

    /// Creates and starts Phase 1 monitoring.
    public init(
        registry: StatusItemRegistry,
        settingsStore: SettingsStore,
        settingsAction: @escaping @MainActor () -> Void,
        quitAction: @escaping @MainActor () -> Void
    ) {
        self.settingsStore = settingsStore
        cpuScheduler = Scheduler(monitor: CPUMonitor())
        memoryScheduler = Scheduler(monitor: MemoryMonitor())

        cpuController = StatusItemController(
            module: .cpu,
            statusItem: registry.item(for: .cpu),
            store: cpuStore,
            settingsStore: settingsStore,
            render: Self.renderCPU
        )
        memoryController = StatusItemController(
            module: .memory,
            statusItem: registry.item(for: .memory),
            store: memoryStore,
            settingsStore: settingsStore,
            render: Self.renderMemory
        )
        cpuDropdown = DropdownController(
            moduleName: ModuleID.cpu.displayName,
            statusItem: registry.item(for: .cpu),
            rootView: AnyView(CPUDropdownView(store: cpuStore)),
            contentHeight: 438,
            tickAction: { [weak cpuStore] in cpuStore?.tick() },
            settingsAction: settingsAction,
            quitAction: quitAction
        )
        memoryDropdown = DropdownController(
            moduleName: ModuleID.memory.displayName,
            statusItem: registry.item(for: .memory),
            rootView: AnyView(MemoryDropdownView(store: memoryStore)),
            contentHeight: 386,
            tickAction: { [weak memoryStore] in memoryStore?.tick() },
            settingsAction: settingsAction,
            quitAction: quitAction
        )

        startSampleConsumption()
        configurePowerAwareness()
        configureDisplaySleepAwareness()
        observeSettings()

        Task {
            await cpuScheduler.start()
            await memoryScheduler.start()
        }
    }

    /// Stops monitor tasks and finishes their streams.
    public func stop() {
        cpuSampleTask?.cancel()
        memorySampleTask?.cancel()
        Task {
            await cpuScheduler.stop()
            await memoryScheduler.stop()
        }
    }

    private func startSampleConsumption() {
        let cpuSamples = cpuScheduler.samples
        cpuSampleTask = Task { [weak self] in
            for await sample in cpuSamples {
                guard !Task.isCancelled else {
                    break
                }
                self?.cpuStore.receive(sample, at: sample.timestamp)
            }
        }

        let memorySamples = memoryScheduler.samples
        memorySampleTask = Task { [weak self] in
            for await sample in memorySamples {
                guard !Task.isCancelled else {
                    break
                }
                self?.memoryStore.receive(sample, at: sample.timestamp)
            }
        }
    }

    private func configurePowerAwareness() {
        powerStateObserver.onChange = { [weak self] state in
            self?.applyPowerState(state)
        }
        applyPowerState(powerStateObserver.currentState)
    }

    private func configureDisplaySleepAwareness() {
        displaySleepWatcher.onSleep = { [weak self] in
            guard let self else {
                return
            }
            Task {
                await self.cpuScheduler.pause()
                await self.memoryScheduler.pause()
            }
        }
        displaySleepWatcher.onWake = { [weak self] in
            guard let self else {
                return
            }
            Task {
                await self.cpuScheduler.resume()
                await self.memoryScheduler.resume()
            }
        }
    }

    private func applyPowerState(_ state: PowerState) {
        let shouldReduce = settingsStore.settings.reducesSamplingOnBattery && state == .batteryPower
        let multiplier = shouldReduce ? 2 : 1
        Task {
            await cpuScheduler.setIntervalMultiplier(multiplier)
            await memoryScheduler.setIntervalMultiplier(multiplier)
        }
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settingsStore.settings.reducesSamplingOnBattery
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else {
                    return
                }
                self.applyPowerState(self.powerStateObserver.currentState)
                self.observeSettings()
            }
        }
    }

    private static func renderCPU(
        sample: CPUSample?,
        history: [HistoryEntry<CPUSample>],
        settings: ModuleSettings,
        context: RenderContext
    ) -> StatusItemContent {
        guard let sample else {
            let image = TextRenderer(
                text: "—",
                reservedText: settings.usesFixedWidth ? "100%" : nil
            ).render(in: context)
            return StatusItemContent(
                image: image,
                accessibilityValue: "CPU unavailable"
            )
        }

        let percentage = String(format: "%.0f%%", sample.totalPercent)
        let renderer: any MenuBarRenderer
        switch settings.mode {
        case "graph":
            renderer = GraphRenderer(
                values: history.map { $0.value.totalPercent / 100 },
                style: settings.graphStyle
            )
        case "perCore":
            renderer = GraphRenderer(
                values: sample.perCore.map { $0.usagePercent / 100 },
                style: .bars,
                width: max(32, CGFloat(sample.perCore.count) * 3)
            )
        case "stacked":
            renderer = StackedLabelRenderer(label: "CPU", value: percentage)
        case "iconText":
            renderer = IconTextRenderer(symbolName: "cpu", text: percentage)
        default:
            renderer = TextRenderer(
                text: percentage,
                reservedText: settings.usesFixedWidth ? "100%" : nil
            )
        }
        return StatusItemContent(
            image: renderer.render(in: context),
            accessibilityValue: String(format: "CPU %.1f percent", sample.totalPercent)
        )
    }

    private static func renderMemory(
        sample: MemorySample?,
        history: [HistoryEntry<MemorySample>],
        settings: ModuleSettings,
        context: RenderContext
    ) -> StatusItemContent {
        guard let sample else {
            let image = TextRenderer(
                text: "—",
                reservedText: settings.usesFixedWidth ? "100%" : nil
            ).render(in: context)
            return StatusItemContent(
                image: image,
                accessibilityValue: "Memory unavailable"
            )
        }

        let usedPercent = sample.total > 0 ? Double(sample.used) / Double(sample.total) * 100 : 0
        let usedText = String(format: "%.0f%%", usedPercent)
        let pressureText = String(format: "%.0f%%", sample.pressurePercent)
        let renderer: any MenuBarRenderer
        switch settings.mode {
        case "pressurePercentage":
            renderer = TextRenderer(
                text: pressureText,
                reservedText: settings.usesFixedWidth ? "100%" : nil
            )
        case "graph":
            renderer = GraphRenderer(
                values: history.map { value in
                    value.value.total > 0 ? Double(value.value.used) / Double(value.value.total) : 0
                },
                style: settings.graphStyle
            )
        case "bar":
            renderer = GraphRenderer(values: [usedPercent / 100], style: .bars, width: 14)
        case "stacked":
            renderer = StackedLabelRenderer(label: "MEM", value: usedText)
        default:
            renderer = TextRenderer(
                text: usedText,
                reservedText: settings.usesFixedWidth ? "100%" : nil
            )
        }
        return StatusItemContent(
            image: renderer.render(in: context),
            accessibilityValue: String(
                format: "Memory %.1f percent used, pressure %.1f percent",
                usedPercent,
                sample.pressurePercent
            )
        )
    }
}
