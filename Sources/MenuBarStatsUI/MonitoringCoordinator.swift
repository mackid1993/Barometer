import AppKit
import CoreLocation
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

    /// Observable Weather state used by its status item and dropdown.
    public let weatherStore = ModuleStore<WeatherSample>(historyCapacity: 192)

    /// Shared application settings.
    public let settingsStore: SettingsStore

    private let cpuScheduler: Scheduler<CPUMonitor>
    private let memoryScheduler: Scheduler<MemoryMonitor>
    private let powerStateObserver = PowerStateObserver()
    private let displaySleepWatcher = DisplaySleepWatcher()
    private var weatherSession: WeatherMonitoringSession?
    private var weatherConfiguration: WeatherConfiguration?
    private var cpuController: StatusItemController<CPUSample>?
    private var memoryController: StatusItemController<MemorySample>?
    private var weatherController: StatusItemController<WeatherSample>?
    private var cpuDropdown: DropdownController?
    private var memoryDropdown: DropdownController?
    private var cpuSampleTask: Task<Void, Never>?
    private var memorySampleTask: Task<Void, Never>?
    private var weatherSampleTask: Task<Void, Never>?
    private var weatherGeneration = 0
    private var isTrackingCurrentLocation = false

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
                    context: context,
                    template: settingsStore.settings.weather.menuBarTemplate
                )
            }
        )
        cpuDropdown = DropdownController(
            moduleName: ModuleID.cpu.displayName,
            statusItem: registry.item(for: .cpu),
            rootView: AnyView(CPUDropdownView(store: cpuStore, settingsStore: settingsStore)),
            contentHeight: 438,
            tickAction: { [weak cpuStore] in cpuStore?.tick() },
            settingsAction: settingsAction,
            quitAction: quitAction
        )
        memoryDropdown = DropdownController(
            moduleName: ModuleID.memory.displayName,
            statusItem: registry.item(for: .memory),
            rootView: AnyView(MemoryDropdownView(store: memoryStore, settingsStore: settingsStore)),
            contentHeight: 386,
            tickAction: { [weak memoryStore] in memoryStore?.tick() },
            settingsAction: settingsAction,
            quitAction: quitAction
        )

        startSampleConsumption()
        configurePowerAwareness()
        configureDisplaySleepAwareness()
        observeSettings()
        configureWeatherMonitoring()
        configureCurrentLocation()

        Task {
            await cpuScheduler.start()
            await memoryScheduler.start()
        }
    }

    /// Stops monitor tasks and finishes their streams.
    public func stop() {
        cpuSampleTask?.cancel()
        memorySampleTask?.cancel()
        weatherSampleTask?.cancel()
        CurrentLocationProvider.shared.stop()
        Task {
            await cpuScheduler.stop()
            await memoryScheduler.stop()
            await weatherSession?.stop()
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
                await self.weatherSession?.pause()
            }
        }
        displaySleepWatcher.onWake = { [weak self] in
            guard let self else {
                return
            }
            Task {
                await self.cpuScheduler.resume()
                await self.memoryScheduler.resume()
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
        }
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settingsStore.settings.reducesSamplingOnBattery
            _ = settingsStore.settings.modules[.cpu]?.interval
            _ = settingsStore.settings.modules[.memory]?.interval
            _ = settingsStore.settings.modules[.weather]?.isEnabled
            _ = settingsStore.settings.weather
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else {
                    return
                }
                self.applyPowerState(self.powerStateObserver.currentState)
                self.applySamplingIntervals()
                self.configureWeatherMonitoring()
                self.configureCurrentLocation()
                self.observeSettings()
            }
        }
        applySamplingIntervals()
    }

    private func applySamplingIntervals() {
        let cpuSeconds = settingsStore.settings.modules[.cpu]?.interval ?? 1
        let memorySeconds = settingsStore.settings.modules[.memory]?.interval ?? 2
        Task {
            await cpuScheduler.setInterval(.milliseconds(Int64(max(0.25, cpuSeconds) * 1_000)))
            await memoryScheduler.setInterval(.milliseconds(Int64(max(0.25, memorySeconds) * 1_000)))
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

    private static func renderWeather(
        sample: WeatherSample?,
        history: [HistoryEntry<WeatherSample>],
        settings: ModuleSettings,
        context: RenderContext,
        template: String
    ) -> StatusItemContent {
        guard let sample else {
            return StatusItemContent(
                image: IconTextRenderer(symbolName: "cloud.sun", text: "—").render(in: context),
                accessibilityValue: "Weather unavailable"
            )
        }
        let forecast = sample.forecast
        let presentation = WeatherPresentationFormatter.menuBar(
            sample: sample,
            mode: settings.mode,
            template: template
        )
        let renderer: any MenuBarRenderer = if let symbolName = presentation.symbolName {
            IconTextRenderer(symbolName: symbolName, text: presentation.text)
        } else {
            TextRenderer(text: presentation.text)
        }
        let temperature = String(format: "%.0f%@", forecast.current.temperature, forecast.units.temperature.symbol)
        let staleDescription = sample.isStale ? ", stale" : ""
        return StatusItemContent(
            image: renderer.render(in: context),
            accessibilityValue: "Weather in \(forecast.location.name), \(temperature), "
                + "\(forecast.current.code.description)\(staleDescription)"
        )
    }

}

private struct WeatherConfiguration: Equatable {
    let location: Location
    let units: WeatherUnits
    let refreshIntervalMinutes: Int
}
