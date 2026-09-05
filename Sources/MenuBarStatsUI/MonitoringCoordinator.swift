import AppKit
import CoreLocation
import MenuBarStatsCore
import Observation
import SwiftUI

/// Wires active monitors, stores, schedulers, and status item controllers together.
@MainActor
public final class MonitoringCoordinator {
    // CPU and Memory expose day-long graphs. Other histories retain only the largest window
    // consumed by their dropdown or status-item graph; full details stay in latestSample.

    /// Observable CPU state used by status items and dropdowns.
    public let cpuStore = ModuleStore<CPUSample>(
        historyCapacity: GraphHistoryRetention.capacity(for: .cpu)
    )

    /// Observable Memory state used by status items and dropdowns.
    public let memoryStore = ModuleStore<MemorySample>(
        historyCapacity: GraphHistoryRetention.capacity(for: .memory)
    )

    /// Observable GPU state used by its status item, dropdown, and settings.
    public let gpuStore = ModuleStore<GPUSample>(
        historyCapacity: GraphHistoryRetention.capacity(for: .gpu)
    )

    /// Observable Weather state used by its status item and dropdown.
    public let weatherStore = ModuleStore<WeatherSample>(
        historyCapacity: GraphHistoryRetention.capacity(for: .weather)
    )

    /// Observable Network state used by its status item, dropdown, and settings.
    public let networkStore = ModuleStore<NetworkSample>(
        historyCapacity: GraphHistoryRetention.capacity(for: .network)
    )

    /// Observable Disk state used by its status item, dropdown, and settings.
    public let diskStore = ModuleStore<DiskSample>(
        historyCapacity: GraphHistoryRetention.capacity(for: .disks)
    )

    /// Observable Sensors state shared by every independently movable Sensors widget.
    public let sensorStore = ModuleStore<SensorSample>(
        historyCapacity: GraphHistoryRetention.capacity(for: .sensors)
    )

    /// Observable Battery state used by its status item, dropdown, and settings.
    public let batteryStore = ModuleStore<BatterySample>(
        historyCapacity: GraphHistoryRetention.capacity(for: .battery)
    )

    /// Observable Time state used by its status item, dropdown, and settings.
    public let timeStore = ModuleStore<TimeSample>(
        historyCapacity: GraphHistoryRetention.capacity(for: .time)
    )

    /// Redraw state for the Combined status item.
    public let combinedStore = ModuleStore<CombinedSample>(
        historyCapacity: GraphHistoryRetention.capacity(for: .combined)
    )

    /// Shared application settings.
    public let settingsStore: SettingsStore

    private let cpuScheduler: Scheduler<CPUMonitor>
    private let memoryScheduler: Scheduler<MemoryMonitor>
    private let gpuScheduler: Scheduler<GPUMonitor>
    private let networkMonitor: NetworkMonitor
    private let networkScheduler: Scheduler<NetworkMonitor>
    private let diskScheduler: Scheduler<DiskMonitor>
    private let sensorsMonitor: SensorsMonitor
    private let sensorsScheduler: Scheduler<SensorsMonitor>
    private let batteryScheduler: Scheduler<BatteryMonitor>
    private let timeMonitor: TimeMonitor
    private var isRequestingCalendarAccess = false
    private let timeScheduler: Scheduler<TimeMonitor>
    private let registry: StatusItemRegistry
    private let settingsAction: @MainActor (ModuleID) -> Void
    private let quitAction: @MainActor () -> Void
    private let powerStateObserver = PowerStateObserver()
    private let displaySleepWatcher = DisplaySleepWatcher()
    private let networkChangeObserver = NetworkChangeObserver()
    private let volumeMountWatcher = VolumeMountWatcher()
    private let timeZoneChangeWatcher = TimeZoneChangeWatcher()
    private var weatherSession: WeatherMonitoringSession?
    private var weatherConfiguration: WeatherConfiguration?
    private var cpuController: StatusItemController<CPUSample>?
    private var memoryController: StatusItemController<MemorySample>?
    private var gpuController: StatusItemController<GPUSample>?
    private var weatherController: StatusItemController<WeatherSample>?
    private var networkController: StatusItemController<NetworkSample>?
    private var diskController: StatusItemController<DiskSample>?
    private var sensorControllers: [Int: StatusItemController<SensorSample>] = [:]
    private var batteryController: StatusItemController<BatterySample>?
    private var timeController: StatusItemController<TimeSample>?
    private var stackControllers: [Int: StatusItemController<CombinedSample>] = [:]
    private var cpuDropdown: DropdownController?
    private var memoryDropdown: DropdownController?
    private var gpuDropdown: DropdownController?
    private var weatherDropdown: DropdownController?
    private var networkDropdown: DropdownController?
    private var diskDropdown: DropdownController?
    private var sensorDropdowns: [Int: DropdownController] = [:]
    private var batteryDropdown: DropdownController?
    private var timeDropdown: DropdownController?
    private var stackDropdowns: [Int: DropdownController] = [:]
    private var cpuSampleTask: Task<Void, Never>?
    private var memorySampleTask: Task<Void, Never>?
    private var gpuSampleTask: Task<Void, Never>?
    private var weatherSampleTask: Task<Void, Never>?
    private var networkSampleTask: Task<Void, Never>?
    private var diskSampleTask: Task<Void, Never>?
    private var sensorSampleTask: Task<Void, Never>?
    private var batterySampleTask: Task<Void, Never>?
    private var timeSampleTask: Task<Void, Never>?
    private var weatherGeneration = 0
    private var isTrackingCurrentLocation = false
    private var lastPublicIPEnabled: Bool?
    private var hasActivatedStatusItems = false

    /// Creates and starts application monitoring.
    public init(
        registry: StatusItemRegistry,
        settingsStore: SettingsStore,
        settingsAction: @escaping @MainActor (ModuleID) -> Void,
        quitAction: @escaping @MainActor () -> Void
    ) {
        self.registry = registry
        self.settingsStore = settingsStore
        self.settingsAction = settingsAction
        self.quitAction = quitAction
        cpuScheduler = Scheduler(monitor: CPUMonitor())
        memoryScheduler = Scheduler(monitor: MemoryMonitor())
        gpuScheduler = Scheduler(monitor: GPUMonitor())
        let networkMonitor = NetworkMonitor()
        self.networkMonitor = networkMonitor
        networkScheduler = Scheduler(monitor: networkMonitor)
        diskScheduler = Scheduler(monitor: DiskMonitor())
        let sensorsMonitor = SensorsMonitor()
        self.sensorsMonitor = sensorsMonitor
        sensorsScheduler = Scheduler(monitor: sensorsMonitor)
        batteryScheduler = Scheduler(monitor: BatteryMonitor())
        let timeMonitor = TimeMonitor()
        self.timeMonitor = timeMonitor
        timeScheduler = Scheduler(monitor: timeMonitor)

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
        let sharedCPUStore = cpuStore
        gpuController = StatusItemController(
            module: .gpu,
            statusItem: registry.item(for: .gpu),
            store: gpuStore,
            settingsStore: settingsStore,
            render: { sample, history, moduleSettings, context in
                GPUMenuBarPresenter.content(
                    sample: sample,
                    history: history,
                    cpuPercent: sharedCPUStore.latestSample?.totalPercent,
                    settings: moduleSettings,
                    context: context
                )
            }
        )
        weatherController = StatusItemController(
            module: .weather,
            statusItem: registry.item(for: .weather),
            store: weatherStore,
            settingsStore: settingsStore,
            render: { sample, history, settings, context in
                Self.renderWeather(
                    sample: sample,
                    history: history,
                    settings: settings,
                    context: context
                )
            }
        )
        networkController = StatusItemController(
            module: .network,
            statusItem: registry.item(for: .network),
            store: networkStore,
            settingsStore: settingsStore,
            render: { sample, history, moduleSettings, context in
                NetworkMenuBarPresenter.content(
                    sample: sample,
                    history: history,
                    moduleSettings: moduleSettings,
                    networkSettings: settingsStore.settings.network,
                    context: context
                )
            }
        )
        diskController = StatusItemController(
            module: .disks,
            statusItem: registry.item(for: .disks),
            store: diskStore,
            settingsStore: settingsStore,
            render: { sample, history, moduleSettings, context in
                DiskMenuBarPresenter.content(
                    sample: sample,
                    history: history,
                    moduleSettings: moduleSettings,
                    diskSettings: settingsStore.settings.disks,
                    context: context
                )
            }
        )
        let sharedBatteryStore = batteryStore
        batteryController = StatusItemController(
            module: .battery,
            statusItem: registry.item(for: .battery),
            store: batteryStore,
            settingsStore: settingsStore,
            isEnabled: { appSettings, moduleSettings in
                guard moduleSettings.isEnabled else { return false }
                return appSettings.battery.showsWhenConnectedToPower
                    || sharedBatteryStore.latestSample?.isExternalConnected != true
            },
            render: { sample, _, moduleSettings, context in
                BatteryMenuBarPresenter.content(
                    sample: sample,
                    moduleSettings: moduleSettings,
                    batterySettings: settingsStore.settings.battery,
                    context: context
                )
            }
        )
        timeController = StatusItemController(
            module: .time,
            statusItem: registry.item(for: .time),
            store: timeStore,
            settingsStore: settingsStore,
            render: { sample, _, moduleSettings, context in
                TimeMenuBarPresenter.content(
                    sample: sample,
                    settings: moduleSettings,
                    timeSettings: settingsStore.settings.time,
                    context: context
                )
            }
        )
        cpuDropdown = DropdownController(
            moduleName: ModuleID.cpu.displayName,
            statusItem: registry.item(for: .cpu),
            rootView: AnyView(CPUDropdownView(store: cpuStore, settingsStore: settingsStore)),
            contentHeight: CPUDropdownView.contentSize.height,
            contentWidth: CPUDropdownView.contentSize.width,
            tickAction: { [weak cpuStore] in cpuStore?.tick() },
            settingsAction: { settingsAction(.cpu) },
            quitAction: quitAction
        )
        memoryDropdown = DropdownController(
            moduleName: ModuleID.memory.displayName,
            statusItem: registry.item(for: .memory),
            rootView: AnyView(MemoryDropdownView(store: memoryStore, settingsStore: settingsStore)),
            contentHeight: MemoryDropdownView.contentSize.height,
            contentWidth: MemoryDropdownView.contentSize.width,
            tickAction: { [weak memoryStore] in memoryStore?.tick() },
            settingsAction: { settingsAction(.memory) },
            quitAction: quitAction
        )
        gpuDropdown = DropdownController(
            moduleName: ModuleID.gpu.displayName,
            statusItem: registry.item(for: .gpu),
            rootView: AnyView(GPUDropdownView(store: gpuStore, settingsStore: settingsStore)),
            contentHeight: GPUDropdownView.contentSize.height,
            contentWidth: GPUDropdownView.contentSize.width,
            tickAction: { [weak gpuStore] in gpuStore?.tick() },
            settingsAction: { settingsAction(.gpu) },
            quitAction: quitAction
        )
        weatherDropdown = DropdownController(
            moduleName: ModuleID.weather.displayName,
            statusItem: registry.item(for: .weather),
            rootView: AnyView(
                WeatherDropdownView(
                    store: weatherStore,
                    settingsStore: settingsStore,
                    refreshAction: { [weak self] in
                        guard let self else {
                            return
                        }
                        Task {
                            await self.weatherSession?.refresh()
                        }
                    }
                )
            ),
            contentHeight: WeatherDropdownView.contentSize.height,
            contentWidth: WeatherDropdownView.contentSize.width,
            usesPopover: true,
            tickAction: { [weak weatherStore] in weatherStore?.tick() },
            settingsAction: { settingsAction(.weather) },
            quitAction: quitAction
        )
        networkDropdown = DropdownController(
            moduleName: ModuleID.network.displayName,
            statusItem: registry.item(for: .network),
            rootView: AnyView(
                NetworkDropdownView(
                    store: networkStore,
                    settingsStore: settingsStore,
                    locationAccess: { CurrentLocationProvider.shared.accessState },
                    locationAction: { [weak self] in self?.handleNetworkLocationAction() }
                )
            ),
            contentHeight: NetworkDropdownView.contentSize.height,
            contentWidth: NetworkDropdownView.contentSize.width,
            tickAction: { [weak networkStore] in networkStore?.tick() },
            settingsAction: { settingsAction(.network) },
            quitAction: quitAction
        )
        diskDropdown = DropdownController(
            moduleName: ModuleID.disks.displayName,
            statusItem: registry.item(for: .disks),
            rootView: AnyView(DiskDropdownView(store: diskStore, settingsStore: settingsStore)),
            contentHeight: DiskDropdownView.contentSize.height,
            contentWidth: DiskDropdownView.contentSize.width,
            tickAction: { [weak diskStore] in diskStore?.tick() },
            settingsAction: { settingsAction(.disks) },
            quitAction: quitAction
        )
        batteryDropdown = DropdownController(
            moduleName: ModuleID.battery.displayName,
            statusItem: registry.item(for: .battery),
            rootView: AnyView(BatteryDropdownView(store: batteryStore, settingsStore: settingsStore)),
            contentHeight: BatteryDropdownView.contentSize.height,
            contentWidth: BatteryDropdownView.contentSize.width,
            tickAction: { [weak batteryStore] in batteryStore?.tick() },
            settingsAction: { settingsAction(.battery) },
            quitAction: quitAction
        )
        timeDropdown = DropdownController(
            moduleName: ModuleID.time.displayName,
            statusItem: registry.item(for: .time),
            rootView: AnyView(
                TimeDropdownView(
                    store: timeStore,
                    weatherStore: weatherStore,
                    settingsStore: settingsStore,
                    requestCalendarAccess: { [weak self] in self?.requestCalendarAccess() }
                )
            ),
            contentHeight: TimeDropdownView.contentSize.height,
            contentWidth: TimeDropdownView.contentSize.width,
            tickAction: { [weak timeStore] in timeStore?.tick() },
            settingsAction: { settingsAction(.time) },
            quitAction: quitAction
        )
        configureSensorWidgets()
        configureStacks()
        activateLaunchStatusItems()

        startSampleConsumption()
        configurePowerAwareness()
        configureDisplaySleepAwareness()
        configureNetworkChangeAwareness()
        configureNetworkLocationAccess()
        configureVolumeMountAwareness()
        configureTimeZoneAwareness()
        observeSettings()
        configureWeatherMonitoring()
        configureCurrentLocation()

        updateSchedulerActivity()
    }

    /// Stops monitor tasks and finishes their streams.
    public func stop() {
        cpuSampleTask?.cancel()
        memorySampleTask?.cancel()
        gpuSampleTask?.cancel()
        weatherSampleTask?.cancel()
        networkSampleTask?.cancel()
        diskSampleTask?.cancel()
        sensorSampleTask?.cancel()
        batterySampleTask?.cancel()
        timeSampleTask?.cancel()
        CurrentLocationProvider.shared.stop()
        CurrentLocationProvider.shared.authorizationDidChange = nil
        timeZoneChangeWatcher.stop()
        Task {
            await cpuScheduler.stop()
            await memoryScheduler.stop()
            await gpuScheduler.stop()
            await networkScheduler.stop()
            await diskScheduler.stop()
            await sensorsScheduler.stop()
            await batteryScheduler.stop()
            await timeScheduler.stop()
            await weatherSession?.stop()
        }
    }

    /// Requests full Calendar access after an explicit user action, then refreshes Time.
    public func requestCalendarAccess() {
        guard !isRequestingCalendarAccess else { return }
        isRequestingCalendarAccess = true
        NSApp.activate(ignoringOtherApps: true)
        Task {
            defer { isRequestingCalendarAccess = false }
            do {
                _ = try await timeMonitor.requestCalendarAccess()
                // Settings can request access even when Time is disabled and its scheduler is paused.
                timeStore.receive(await timeMonitor.sample())
            } catch {
                let alert = NSAlert()
                alert.messageText = "Calendar access could not be requested"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    private func recordCombinedUpdate(from module: ModuleID, at timestamp: Date) {
        guard settingsStore.settings.stacks.needsSample(from: module) else { return }
        combinedStore.receive(CombinedSample(), at: timestamp)
    }

    private func startSampleConsumption() {
        let cpuSamples = cpuScheduler.samples
        cpuSampleTask = Task { [weak self] in
            for await sample in cpuSamples {
                guard !Task.isCancelled else {
                    break
                }
                self?.cpuStore.receive(sample, at: sample.timestamp)
                self?.recordCombinedUpdate(from: .cpu, at: sample.timestamp)
            }
        }

        let memorySamples = memoryScheduler.samples
        memorySampleTask = Task { [weak self] in
            for await sample in memorySamples {
                guard !Task.isCancelled else {
                    break
                }
                self?.memoryStore.receive(sample, at: sample.timestamp)
                self?.recordCombinedUpdate(from: .memory, at: sample.timestamp)
            }
        }

        let gpuSamples = gpuScheduler.samples
        gpuSampleTask = Task { [weak self] in
            for await sample in gpuSamples {
                guard !Task.isCancelled else { break }
                self?.gpuStore.receive(sample, at: sample.timestamp)
                self?.recordCombinedUpdate(from: .gpu, at: sample.timestamp)
            }
        }

        let networkSamples = networkScheduler.samples
        networkSampleTask = Task { [weak self] in
            for await sample in networkSamples {
                guard !Task.isCancelled else {
                    break
                }
                self?.networkStore.receive(sample, at: sample.timestamp)
                self?.recordCombinedUpdate(from: .network, at: sample.timestamp)
            }
        }

        let diskSamples = diskScheduler.samples
        diskSampleTask = Task { [weak self] in
            for await sample in diskSamples {
                guard !Task.isCancelled else {
                    break
                }
                self?.diskStore.receive(sample, at: sample.timestamp)
                self?.recordCombinedUpdate(from: .disks, at: sample.timestamp)
            }
        }

        let sensorSamples = sensorsScheduler.samples
        sensorSampleTask = Task { [weak self] in
            for await sample in sensorSamples {
                guard !Task.isCancelled else {
                    break
                }
                self?.sensorStore.receive(sample, at: sample.timestamp)
                self?.recordCombinedUpdate(from: .sensors, at: sample.timestamp)
            }
        }

        let batterySamples = batteryScheduler.samples
        batterySampleTask = Task { [weak self] in
            for await sample in batterySamples {
                guard !Task.isCancelled else { break }
                self?.batteryStore.receive(sample, at: sample.timestamp)
                self?.recordCombinedUpdate(from: .battery, at: sample.timestamp)
            }
        }

        let timeSamples = timeScheduler.samples
        timeSampleTask = Task { [weak self] in
            for await sample in timeSamples {
                guard !Task.isCancelled else { break }
                self?.timeStore.receive(sample, at: sample.timestamp)
                self?.recordCombinedUpdate(from: .time, at: sample.timestamp)
            }
        }
    }

    private func configurePowerAwareness() {
        powerStateObserver.onChange = { [weak self] state in
            self?.applyPowerState(state)
        }
        applyPowerState(powerStateObserver.currentState)
    }

    private func configureTimeZoneAwareness() {
        timeZoneChangeWatcher.onChange = { [weak self] in
            guard let self else { return }
            Task {
                await self.timeScheduler.refresh()
            }
        }
    }

    private func configureDisplaySleepAwareness() {
        displaySleepWatcher.onSleep = { [weak self] in
            guard let self else {
                return
            }
            Task {
                await self.cpuScheduler.pause()
                await self.memoryScheduler.pause()
                await self.gpuScheduler.pause()
                await self.networkScheduler.pause()
                await self.diskScheduler.pause()
                await self.sensorsScheduler.pause()
                await self.batteryScheduler.pause()
                await self.timeScheduler.pause()
                await self.weatherSession?.pause()
            }
        }
        displaySleepWatcher.onWake = { [weak self] in
            guard let self else {
                return
            }
            Task {
                self.updateSchedulerActivity()
                await self.weatherSession?.resume()
            }
        }
    }

    private func applyPowerState(_ state: PowerState) {
        let shouldReduce = settingsStore.settings.reducesSamplingOnBattery && state == .batteryPower
        let multiplier = shouldReduce ? 2 : 1
        Task {
            await cpuScheduler.setIntervalMultiplier(multiplier)
            await memoryScheduler.setIntervalMultiplier(multiplier)
            await gpuScheduler.setIntervalMultiplier(multiplier)
            await networkScheduler.setIntervalMultiplier(multiplier)
            await diskScheduler.setIntervalMultiplier(multiplier)
            await sensorsScheduler.setIntervalMultiplier(multiplier)
            await batteryScheduler.setIntervalMultiplier(multiplier)
            await batteryScheduler.refresh()
        }
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settingsStore.settings.reducesSamplingOnBattery
            _ = settingsStore.settings.modules
            _ = settingsStore.settings.combined
            _ = settingsStore.settings.stacks
            _ = settingsStore.settings.modules[.cpu]?.interval
            _ = settingsStore.settings.modules[.memory]?.interval
            _ = settingsStore.settings.modules[.gpu]?.interval
            _ = settingsStore.settings.modules[.weather]?.isEnabled
            _ = settingsStore.settings.modules[.network]?.interval
            _ = settingsStore.settings.modules[.disks]?.interval
            _ = settingsStore.settings.modules[.sensors]?.interval
            _ = settingsStore.settings.modules[.battery]?.interval
            _ = settingsStore.settings.modules[.time]?.isEnabled
            _ = settingsStore.settings.weather
            _ = settingsStore.settings.network
            _ = settingsStore.settings.disks
            _ = settingsStore.settings.sensors
            _ = settingsStore.settings.sensorTemperatureUnit
            _ = settingsStore.settings.battery
            _ = settingsStore.settings.time
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else {
                    return
                }
                self.prepareNewlyEnabledItems()
                self.applyPowerState(self.powerStateObserver.currentState)
                self.applySamplingIntervals()
                self.updateSchedulerActivity()
                self.configureWeatherMonitoring()
                self.configureCurrentLocation()
                self.applyNetworkSettings()
                self.configureSensorWidgets()
                self.configureStacks()
                self.observeSettings()
            }
        }
        applySamplingIntervals()
        applyNetworkSettings()
    }

    private func updateSchedulerActivity() {
        let active = Self.modulesRequiringSamples(settingsStore.settings)
        Task {
            await setScheduler(cpuScheduler, active: active.contains(.cpu))
            await setScheduler(memoryScheduler, active: active.contains(.memory))
            await setScheduler(gpuScheduler, active: active.contains(.gpu))
            await setScheduler(networkScheduler, active: active.contains(.network))
            await setScheduler(diskScheduler, active: active.contains(.disks))
            await setScheduler(sensorsScheduler, active: active.contains(.sensors))
            await setScheduler(batteryScheduler, active: active.contains(.battery))
            await setScheduler(timeScheduler, active: active.contains(.time))
        }
    }

    private func setScheduler<Source: Monitor>(_ scheduler: Scheduler<Source>, active: Bool) async {
        if active {
            await scheduler.resume()
        } else {
            await scheduler.pause()
        }
    }

    static func modulesRequiringSamples(_ settings: AppSettings) -> Set<ModuleID> {
        var active = Set(
            ModuleID.allCases.filter { module in
                module != .weather && module != .combined && settings.modules[module]?.isEnabled == true
            })
        // A stack keeps its source modules sampling even when their individual items are hidden.
        for stack in settings.enabledStacks {
            active.formUnion(stack.sourceModules.filter { $0 != .weather && $0 != .combined })
        }
        if settings.modules[.gpu]?.mode == "combinedCPU", active.contains(.gpu) {
            active.insert(.cpu)
        }
        return active
    }

    private func applySamplingIntervals() {
        let cpuSeconds = settingsStore.settings.modules[.cpu]?.interval ?? 1
        let memorySeconds = settingsStore.settings.modules[.memory]?.interval ?? 2
        let gpuSeconds = settingsStore.settings.modules[.gpu]?.interval ?? 1
        let networkSeconds = settingsStore.settings.modules[.network]?.interval ?? 1
        let diskSeconds = settingsStore.settings.modules[.disks]?.interval ?? 1
        let sensorSeconds = settingsStore.settings.modules[.sensors]?.interval ?? 5
        let batterySeconds = settingsStore.settings.modules[.battery]?.interval ?? 10
        let timeShowsSeconds = settingsStore.settings.time.showsSeconds
        let timeShowsCalendarEvents = settingsStore.settings.time.showsCalendarEvents
        let calendarEventCount = settingsStore.settings.time.calendarEventCount
        Task {
            await cpuScheduler.setInterval(.milliseconds(Int64(max(0.25, cpuSeconds) * 1_000)))
            await memoryScheduler.setInterval(.milliseconds(Int64(max(0.25, memorySeconds) * 1_000)))
            await gpuScheduler.setInterval(.milliseconds(Int64(max(0.5, gpuSeconds) * 1_000)))
            await networkScheduler.setInterval(.milliseconds(Int64(max(0.25, networkSeconds) * 1_000)))
            await diskScheduler.setInterval(.milliseconds(Int64(max(0.25, diskSeconds) * 1_000)))
            await sensorsScheduler.setInterval(.milliseconds(Int64(max(5, sensorSeconds) * 1_000)))
            await batteryScheduler.setInterval(.milliseconds(Int64(max(2, batterySeconds) * 1_000)))
            await timeMonitor.setShowsSeconds(timeShowsSeconds)
            await timeMonitor.setCalendarConfiguration(
                isEnabled: timeShowsCalendarEvents,
                count: calendarEventCount
            )
            await timeScheduler.setInterval(nil)
            await timeScheduler.refresh()
        }
    }

    private func configureSensorWidgets() {
        let sharedSettingsStore = settingsStore
        let enabledIdentities = StatusItemRegistry.launchIdentities(settings: settingsStore.settings)
            .filter { $0.module == .sensors }
        for identity in enabledIdentities where sensorControllers[identity.instance] == nil {
            guard let widget = settingsStore.settings.sensors.widget(id: identity.instance) else {
                continue
            }
            let instance = widget.id
            let statusItem = registry.prepareItem(for: identity)
            let controller = StatusItemController(
                module: .sensors,
                statusItem: statusItem,
                store: sensorStore,
                settingsStore: settingsStore,
                isEnabled: { appSettings, moduleSettings in
                    moduleSettings.isEnabled && appSettings.sensors.widget(id: instance)?.isEnabled == true
                },
                render: { sample, history, moduleSettings, context in
                    guard let currentWidget = sharedSettingsStore.settings.sensors.widget(id: instance) else {
                        return StatusItemContent(
                            image: TextRenderer(text: "—").render(in: context),
                            accessibilityValue: "Sensors widget unavailable"
                        )
                    }
                    return SensorsMenuBarPresenter.content(
                        sample: sample,
                        history: history,
                        moduleSettings: moduleSettings,
                        sensorSettings: sharedSettingsStore.settings.sensors,
                        widget: currentWidget,
                        temperatureUnit: sharedSettingsStore.settings.sensorTemperatureUnit,
                        context: context
                    )
                }
            )
            sensorControllers[instance] = controller
            sensorDropdowns[instance] = DropdownController(
                moduleName: ModuleID.sensors.displayName(instance: instance),
                statusItem: statusItem,
                rootView: AnyView(
                    SensorsDropdownView(
                        store: sensorStore,
                        settingsStore: settingsStore,
                        resetEnergyAction: { [weak self] in
                            guard let self else { return }
                            Task {
                                await self.sensorsMonitor.resetSessionEnergy()
                                await self.sensorsScheduler.refresh()
                            }
                        }
                    )
                ),
                contentHeight: SensorsDropdownView.contentSize.height,
                contentWidth: SensorsDropdownView.contentSize.width,
                tickAction: { [weak sensorStore] in sensorStore?.tick() },
                settingsAction: { self.settingsAction(.sensors) },
                quitAction: quitAction
            )
            if hasActivatedStatusItems {
                controller.activateVisibility()
            }
        }
    }

    /// Creates a status item, controller, and dropdown for every enabled stack.
    ///
    /// Mirrors `configureSensorWidgets`: identities are permanent and ids are never reused, so a
    /// stack added later can never inherit a removed stack's saved menu bar position.
    private func configureStacks() {
        let enabledIdentities = StatusItemRegistry.launchIdentities(settings: settingsStore.settings)
            .filter { $0.module == .combined }
        for identity in enabledIdentities where stackControllers[identity.instance] == nil {
            let instance = identity.instance
            let statusItem = registry.prepareItem(for: identity)
            let controller = StatusItemController(
                module: .combined,
                statusItem: statusItem,
                store: combinedStore,
                settingsStore: settingsStore,
                isEnabled: { appSettings, moduleSettings in
                    moduleSettings.isEnabled && appSettings.stacks.stack(id: instance)?.isEnabled == true
                },
                render: { [weak self] _, _, _, context in
                    self?.renderStack(id: instance, context: context)
                        ?? StatusItemContent(
                            image: TextRenderer(text: "—").render(in: context),
                            accessibilityValue: "Stack unavailable"
                        )
                }
            )
            stackControllers[instance] = controller
            stackDropdowns[instance] = DropdownController(
                moduleName: ModuleID.combined.displayName(instance: instance),
                statusItem: statusItem,
                rootView: AnyView(
                    CombinedDropdownView(
                        stackID: instance,
                        cpuStore: cpuStore,
                        memoryStore: memoryStore,
                        gpuStore: gpuStore,
                        networkStore: networkStore,
                        diskStore: diskStore,
                        sensorStore: sensorStore,
                        batteryStore: batteryStore,
                        weatherStore: weatherStore,
                        timeStore: timeStore,
                        settingsStore: settingsStore,
                        locationAccess: { CurrentLocationProvider.shared.accessState },
                        locationAction: { [weak self] in self?.handleNetworkLocationAction() },
                        weatherRefreshAction: { [weak self] in
                            guard let self else { return }
                            Task { await self.weatherSession?.refresh() }
                        },
                        resetEnergyAction: { [weak self] in
                            guard let self else { return }
                            Task {
                                await self.sensorsMonitor.resetSessionEnergy()
                                await self.sensorsScheduler.refresh()
                            }
                        },
                        requestCalendarAccess: { [weak self] in self?.requestCalendarAccess() }
                    )
                ),
                contentHeight: CombinedDropdownView.contentSize.height,
                contentWidth: CombinedDropdownView.contentSize.width,
                usesPopover: true,
                tickAction: { [weak combinedStore] in combinedStore?.tick() },
                settingsAction: { self.settingsAction(.combined) },
                quitAction: quitAction
            )
            if hasActivatedStatusItems {
                controller.activateVisibility()
            }
        }
    }

    /// Reveals the complete launch set only after every item has its final image, length, menu, and identity.
    /// The order must match registry construction so external managers never observe conflicting ordinals.
    private func activateLaunchStatusItems() {
        for identity in StatusItemRegistry.launchIdentities(settings: settingsStore.settings) {
            switch identity.module {
            case .cpu:
                cpuController?.activateVisibility()
            case .gpu:
                gpuController?.activateVisibility()
            case .memory:
                memoryController?.activateVisibility()
            case .disks:
                diskController?.activateVisibility()
            case .network:
                networkController?.activateVisibility()
            case .sensors:
                sensorControllers[identity.instance]?.activateVisibility()
            case .battery:
                batteryController?.activateVisibility()
            case .weather:
                weatherController?.activateVisibility()
            case .time:
                timeController?.activateVisibility()
            case .combined:
                stackControllers[identity.instance]?.activateVisibility()
            }
        }
        hasActivatedStatusItems = true
    }

    private func prepareNewlyEnabledItems() {
        for identity in StatusItemRegistry.launchIdentities(settings: settingsStore.settings)
            where identity.module != .sensors && identity.module != .combined
        {
            let statusItem = registry.prepareItem(for: identity)
            switch identity.module {
            case .cpu:
                attach(statusItem, controller: cpuController, dropdown: cpuDropdown)
            case .gpu:
                attach(statusItem, controller: gpuController, dropdown: gpuDropdown)
            case .memory:
                attach(statusItem, controller: memoryController, dropdown: memoryDropdown)
            case .disks:
                attach(statusItem, controller: diskController, dropdown: diskDropdown)
            case .network:
                attach(statusItem, controller: networkController, dropdown: networkDropdown)
            case .battery:
                attach(statusItem, controller: batteryController, dropdown: batteryDropdown)
            case .weather:
                attach(statusItem, controller: weatherController, dropdown: weatherDropdown)
            case .time:
                attach(statusItem, controller: timeController, dropdown: timeDropdown)
            case .combined, .sensors:
                break
            }
        }
        configureSensorWidgets()
        configureStacks()
    }

    private func attach<Sample: Sendable>(
        _ statusItem: NSStatusItem,
        controller: StatusItemController<Sample>?,
        dropdown: DropdownController?
    ) {
        dropdown?.attach(statusItem: statusItem)
        controller?.attach(statusItem: statusItem)
        if hasActivatedStatusItems {
            controller?.activateVisibility()
        }
    }

    private func configureNetworkChangeAwareness() {
        networkChangeObserver.onChange = { [weak self] in
            guard let self else {
                return
            }
            Task {
                await self.networkMonitor.refreshConnectionDetails()
                await self.networkMonitor.refreshPublicIP()
                await self.networkScheduler.refresh()
            }
        }
    }

    private func configureNetworkLocationAccess() {
        let provider = CurrentLocationProvider.shared
        provider.authorizationDidChange = { [weak self] state in
            guard let self else {
                return
            }
            networkStore.tick()
            if state == .authorized {
                refreshNetworkIdentity()
            }
        }
        if provider.accessState == .authorized {
            refreshNetworkIdentity()
        }
    }

    private func handleNetworkLocationAction() {
        let provider = CurrentLocationProvider.shared
        switch provider.accessState {
        case .notDetermined:
            provider.requestAuthorizationIfNeeded()
        case .authorized, .unavailable:
            refreshNetworkIdentity()
        case .denied, .restricted:
            guard let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
            ) else {
                return
            }
            NSWorkspace.shared.open(url)
        }
    }

    private func refreshNetworkIdentity() {
        Task {
            await networkMonitor.refreshConnectionDetails()
            await networkScheduler.refresh()
        }
    }

    private func configureVolumeMountAwareness() {
        volumeMountWatcher.onChange = { [weak self] in
            guard let self else {
                return
            }
            Task {
                await self.diskScheduler.refresh()
            }
        }
    }

    private func applyNetworkSettings() {
        let isPublicIPEnabled = settingsStore.settings.network.showsPublicIP
        let didChange = lastPublicIPEnabled != isPublicIPEnabled
        lastPublicIPEnabled = isPublicIPEnabled
        Task {
            await networkMonitor.setPublicIPEnabled(isPublicIPEnabled)
            if didChange {
                await networkScheduler.refresh()
            }
        }
    }

    private func configureWeatherMonitoring() {
        let appSettings = settingsStore.settings
        let isEnabled = appSettings.modules[.weather]?.isEnabled == true
        guard isEnabled, let location = appSettings.weather.primaryLocation else {
            stopWeatherMonitoring()
            return
        }
        let configuration = WeatherConfiguration(
            location: location,
            units: appSettings.weather.units,
            refreshIntervalMinutes: max(5, min(60, appSettings.weather.refreshIntervalMinutes))
        )
        guard configuration != weatherConfiguration else {
            return
        }

        stopWeatherMonitoring()
        weatherConfiguration = configuration
        weatherGeneration += 1
        let generation = weatherGeneration
        let monitor = WeatherMonitor(
            location: location,
            units: configuration.units,
            refreshInterval: .seconds(configuration.refreshIntervalMinutes * 60)
        )
        let session = WeatherMonitoringSession(monitor: monitor)
        weatherSession = session
        let samples = session.samples
        weatherSampleTask = Task { [weak self] in
            await session.start()
            for await sample in samples {
                guard !Task.isCancelled, let self, self.weatherGeneration == generation else {
                    break
                }
                self.weatherStore.receive(sample, at: sample.timestamp)
                self.recordCombinedUpdate(from: .weather, at: sample.timestamp)
            }
        }
    }

    private func stopWeatherMonitoring() {
        weatherGeneration += 1
        weatherConfiguration = nil
        weatherSampleTask?.cancel()
        weatherSampleTask = nil
        let previousSession = weatherSession
        weatherSession = nil
        weatherStore.reset()
        Task {
            await previousSession?.stop()
        }
    }

    private func configureCurrentLocation() {
        let shouldTrack = settingsStore.settings.weather.usesCurrentLocation
        guard shouldTrack != isTrackingCurrentLocation else {
            return
        }
        isTrackingCurrentLocation = shouldTrack
        guard shouldTrack else {
            CurrentLocationProvider.shared.stop()
            return
        }
        CurrentLocationProvider.shared.start { [weak self] location in
            self?.updateCurrentLocation(location)
        } failure: { [weak self] _ in
            guard let self else {
                return
            }
            var appSettings = self.settingsStore.settings
            appSettings.weather.usesCurrentLocation = false
            self.settingsStore.settings = appSettings
        }
    }

    private func updateCurrentLocation(_ value: CLLocation) {
        let location = Location(
            id: "current-location",
            name: "Current Location",
            admin: nil,
            country: "",
            latitude: value.coordinate.latitude,
            longitude: value.coordinate.longitude,
            timeZone: TimeZone.current.identifier
        )
        var appSettings = settingsStore.settings
        appSettings.weather.locations.removeAll { $0.id == location.id }
        appSettings.weather.locations.insert(location, at: 0)
        appSettings.weather.primaryLocationID = location.id
        settingsStore.settings = appSettings
    }

    static func renderCPU(
        sample: CPUSample?,
        history: [HistoryEntry<CPUSample.GraphValue>],
        settings: ModuleSettings,
        context: RenderContext
    ) -> StatusItemContent {
        let percentage = sample.map { String(format: "%.0f%%", $0.totalPercent) } ?? "—"
        let renderer: any MenuBarRenderer
        switch settings.mode {
        case "graph":
            renderer = GraphRenderer(
                values: history.map { $0.value.totalPercent / 100 },
                style: settings.graphStyle
            )
        case "perCore":
            let coreValues =
                sample?.perCore.map { $0.usagePercent / 100 }
                ?? Array(repeating: 0, count: ProcessInfo.processInfo.activeProcessorCount)
            renderer = GraphRenderer(
                values: coreValues,
                style: .bars,
                width: max(32, CGFloat(coreValues.count) * 3)
            )
        case "stacked":
            renderer = StackedLabelRenderer(label: "CPU", value: percentage, reservedValue: "100%")
        case "iconText":
            renderer = IconTextRenderer(symbolName: "cpu", text: percentage, reservedText: "100%")
        default:
            renderer = TextRenderer(
                text: percentage,
                reservedText: settings.usesFixedWidth ? "100%" : nil
            )
        }
        guard let sample else {
            return StatusItemContent(image: renderer.render(in: context), accessibilityValue: "CPU unavailable")
        }
        return StatusItemContent(
            image: renderer.render(in: context),
            accessibilityValue: String(format: "CPU %.1f percent", sample.totalPercent)
        )
    }

    static func renderMemory(
        sample: MemorySample?,
        history: [HistoryEntry<MemorySample.GraphValue>],
        settings: ModuleSettings,
        context: RenderContext
    ) -> StatusItemContent {
        let usedPercent = sample.map { $0.total > 0 ? Double($0.used) / Double($0.total) * 100 : 0 } ?? 0
        let usedText = sample.map { _ in String(format: "%.0f%%", usedPercent) } ?? "—"
        let pressureText = sample.map { String(format: "%.0f%%", $0.pressurePercent) } ?? "—"
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
                    value.value.usedFraction
                },
                style: settings.graphStyle
            )
        case "bar":
            renderer = GraphRenderer(values: [usedPercent / 100], style: .bars, width: 14)
        case "stacked":
            renderer = StackedLabelRenderer(label: "MEM", value: usedText, reservedValue: "100%")
        default:
            renderer = TextRenderer(
                text: usedText,
                reservedText: settings.usesFixedWidth ? "100%" : nil
            )
        }
        guard let sample else {
            return StatusItemContent(image: renderer.render(in: context), accessibilityValue: "Memory unavailable")
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

    /// Builds one stack's status item content from its chosen metrics.
    private func renderStack(id: Int, context: RenderContext) -> StatusItemContent {
        let appSettings = settingsStore.settings
        guard let stack = appSettings.stacks.stack(id: id) else {
            return StatusItemContent(
                image: TextRenderer(text: "—").render(in: context),
                accessibilityValue: "Stack unavailable"
            )
        }
        let values = stack.metrics.map { metric in
            ResolvedStackMetric(
                metric: metric,
                value: stackValue(for: metric, appSettings: appSettings)
            )
        }
        return StackMenuBarPresenter.content(stack: stack, values: values, context: context)
    }

    /// Resolves one metric against the live stores.
    ///
    /// Every branch returns the same reserved width whether or not a sample has arrived, so an item
    /// never resizes as its module starts sampling.
    private func stackValue(for metric: StackMetric, appSettings: AppSettings) -> SensorStackValue {
        // The reserved width comes from the shared catalog, so the Settings preview and the item
        // itself can never disagree about how wide a reading is.
        func field(_ value: String?) -> SensorStackValue {
            SensorStackValue(
                label: metric.label,
                value: value ?? "—",
                reservedValue: metric.reservedValue(settings: appSettings),
                reservedLabel: metric.label
            )
        }
        func percent(_ value: Double?) -> SensorStackValue {
            field(value.map { String(format: "%.0f%%", $0) })
        }

        let disks = appSettings.disks
        let network = appSettings.network
        let temperatureUnit = appSettings.sensorTemperatureUnit

        switch metric {
        case .cpuTotal:
            return percent(cpuStore.latestSample?.totalPercent)
        case .cpuUser:
            return percent(cpuStore.latestSample?.userPercent)
        case .cpuSystem:
            return percent(cpuStore.latestSample?.systemPercent)
        case .cpuIdle:
            return percent(cpuStore.latestSample?.idlePercent)
        case .cpuLoad:
            return field(cpuStore.latestSample?.loadAverages.first.map { String(format: "%.2f", $0) })
        case .gpuUtilization:
            return percent(gpuStore.latestSample?.deviceUtilizationPercent)
        case .gpuPower:
            return field(gpuStore.latestSample?.powerWatts.map { String(format: "%.1fW", $0) })
        case .gpuTemperature:
            return field(gpuStore.latestSample?.temperatureCelsius.map { Self.temperature($0, unit: temperatureUnit) })
        case .memoryUsedPercent:
            return percent(
                memoryStore.latestSample.map { $0.total > 0 ? Double($0.used) / Double($0.total) * 100 : 0 }
            )
        case .memoryUsedBytes:
            return field(
                memoryStore.latestSample.map {
                    DiskValueFormatter.capacity($0.used, unitSystem: disks.unitSystem, compact: true)
                }
            )
        case .memoryFreeBytes:
            return field(
                memoryStore.latestSample.map {
                    DiskValueFormatter.capacity($0.free, unitSystem: disks.unitSystem, compact: true)
                }
            )
        case .memoryPressure:
            return percent(memoryStore.latestSample?.pressurePercent)
        case .memorySwap:
            return field(
                memoryStore.latestSample.map {
                    DiskValueFormatter.capacity($0.swapUsed, unitSystem: disks.unitSystem, compact: true)
                }
            )
        case .diskRead:
            return field(
                diskStore.latestSample.map {
                    DiskValueFormatter.rate(Self.diskRates($0).read, unitSystem: disks.unitSystem, compact: true)
                }
            )
        case .diskWrite:
            return field(
                diskStore.latestSample.map {
                    DiskValueFormatter.rate(Self.diskRates($0).write, unitSystem: disks.unitSystem, compact: true)
                }
            )
        case .diskUsedPercent:
            return percent(diskStore.latestSample?.selectedVolume(settings: disks)?.usedPercent)
        case .diskFreeBytes:
            return field(
                diskStore.latestSample?.selectedVolume(settings: disks).map {
                    DiskValueFormatter.capacity($0.availableBytes, unitSystem: disks.unitSystem, compact: true)
                }
            )
        case .networkDownload:
            return field(
                networkStore.latestSample?.interface(named: network.selectedInterfaceName).map {
                    NetworkRateFormatter.compactString(
                        bytesPerSecond: $0.downloadBytesPerSecond,
                        unit: network.rateUnit,
                        decimalPlaces: network.decimalPlaces
                    )
                }
            )
        case .networkUpload:
            return field(
                networkStore.latestSample?.interface(named: network.selectedInterfaceName).map {
                    NetworkRateFormatter.compactString(
                        bytesPerSecond: $0.uploadBytesPerSecond,
                        unit: network.rateUnit,
                        decimalPlaces: network.decimalPlaces
                    )
                }
            )
        case .sensorsHottest, .sensorsFan:
            let reading =
                metric == .sensorsFan
                ? sensorStore.latestSample?.readings.first { $0.kind == .fan }
                : sensorStore.latestSample?.reading(id: "derived:temperature:hottest")
            return field(
                reading.map {
                    SensorValueFormatter.string(
                        $0,
                        temperatureUnit: temperatureUnit,
                        decimalPlaces: appSettings.sensors.decimalPlaces,
                        compact: true
                    )
                }
            )
        case .batteryCharge:
            return percent(batteryStore.latestSample?.chargePercent)
        case .batteryTime:
            return field(batteryStore.latestSample.map { BatteryTimeFormatter.compact(minutes: $0.remainingMinutes) })
        case .weatherTemperature:
            return field(
                weatherStore.latestSample.map {
                    WeatherPresentationFormatter.degree($0.forecast.current.temperature)
                }
            )
        case .timeClock:
            return field(
                timeStore.latestSample.flatMap { sample in
                    TimeZone(identifier: sample.systemTimeZoneIdentifier).map { zone in
                        TimeFormatEngine.render(
                            date: sample.timestamp,
                            timeZone: zone,
                            template: appSettings.time.menuBarTemplate,
                            showsSeconds: appSettings.time.showsSeconds
                        )
                    }
                }
            )
        }
    }

    private static func temperature(_ celsius: Double, unit: TemperatureUnit) -> String {
        let value = unit == .fahrenheit ? celsius * 9 / 5 + 32 : celsius
        return String(format: "%.0f%@", value, unit.symbol)
    }

    private static func diskRates(_ sample: DiskSample) -> (read: Double, write: Double) {
        sample.devices.reduce(into: (read: 0.0, write: 0.0)) { totals, device in
            totals.read += device.readBytesPerSecond
            totals.write += device.writeBytesPerSecond
        }
    }


    static func renderWeather(
        sample: WeatherSample?,
        history: [HistoryEntry<WeatherSample.GraphValue>],
        settings: ModuleSettings,
        context: RenderContext
    ) -> StatusItemContent {
        // Weather has one presentation: the current condition glyph beside the current
        // temperature. The alternatives were either unreadable at this size or variations of
        // the same reading, and one well-made option beats a menu of mediocre ones.
        let presentation =
            sample.map(WeatherPresentationFormatter.menuBar)
            ?? WeatherMenuBarPresentation(symbolName: "cloud.sun", text: "\u{2014}")
        let renderer = IconTextRenderer(
            symbolName: presentation.symbolName ?? "cloud.sun",
            text: presentation.text,
            reservedText: WeatherPresentationFormatter.reservedMenuBarText,
            // Every condition glyph is reserved, so the item keeps one width as conditions change.
            reservedSymbolNames: weatherSymbolNames
        )
        guard let sample else {
            return StatusItemContent(
                image: renderer.render(in: context),
                accessibilityValue: "Weather unavailable"
            )
        }
        let forecast = sample.forecast
        let temperature = String(
            format: "%.0f%@",
            forecast.current.temperature,
            forecast.units.temperature.symbol
        )
        let staleDescription = sample.isStale ? ", stale" : ""
        return StatusItemContent(
            image: renderer.render(in: context),
            accessibilityValue: "Weather in \(forecast.location.name), \(temperature), "
                + "\(forecast.current.code.description)\(staleDescription)"
        )
    }

    private static let weatherSymbolNames = [
        "sun.max", "moon.stars", "cloud.sun", "cloud.moon", "cloud", "cloud.fog", "cloud.drizzle",
        "cloud.rain", "cloud.sleet", "cloud.snow", "cloud.heavyrain", "cloud.bolt.rain", "questionmark.circle",
    ]

}

private struct WeatherConfiguration: Equatable {
    let location: Location
    let units: WeatherUnits
    let refreshIntervalMinutes: Int
}
