import AppKit
import SystemSources
import Testing

@testable import MenuBarStatsCore
@testable import MenuBarStatsUI

@MainActor
struct MenuBarRendererTests {
    private let context = RenderContext(
        thickness: 24,
        appearance: .dark,
        palette: MenuBarPalette(light: .black, dark: .white),
        fontSize: 12.65,
        isMonochrome: true,
        scale: 1.15
    )

    @Test
    func batteryPresentationUsesStablePercentageGlyphWidth() {
        let snapshot = BatterySnapshot(
            name: "Internal Battery",
            chargePercent: 42,
            state: .discharging,
            isExternalConnected: false,
            isCharging: false,
            isFullyCharged: false,
            healthPercent: 98,
            cycleCount: 45,
            temperatureCelsius: 31,
            voltageVolts: 12.4,
            amperageAmps: -1.2,
            wattageWatts: -14.9,
            condition: "Good",
            adapter: nil,
            isLowPowerModeEnabled: false
        )
        let sample = BatterySample(snapshot: snapshot)

        let low = BatteryMenuBarPresenter.content(
            sample: sample,
            moduleSettings: ModuleSettings(isEnabled: true, mode: "glyphPercentage"),
            batterySettings: BatterySettings(),
            context: context
        )
        let fullSnapshot = BatterySnapshot(
            name: snapshot.name,
            chargePercent: 100,
            state: .full,
            isExternalConnected: true,
            isCharging: false,
            isFullyCharged: true,
            healthPercent: snapshot.healthPercent,
            cycleCount: snapshot.cycleCount,
            temperatureCelsius: snapshot.temperatureCelsius,
            voltageVolts: snapshot.voltageVolts,
            amperageAmps: 0,
            wattageWatts: 0,
            condition: snapshot.condition,
            adapter: nil,
            isLowPowerModeEnabled: false
        )
        let full = BatteryMenuBarPresenter.content(
            sample: BatterySample(snapshot: fullSnapshot),
            moduleSettings: ModuleSettings(isEnabled: true, mode: "glyphPercentage"),
            batterySettings: BatterySettings(),
            context: context
        )
        #expect(low.image.size.width > 0)
        #expect(low.accessibilityValue.contains("Battery 42.0 percent"))
        #expect(low.image.size == full.image.size)

        let unavailable = BatteryMenuBarPresenter.content(
            sample: nil,
            moduleSettings: ModuleSettings(isEnabled: true, mode: "glyphPercentage"),
            batterySettings: BatterySettings(),
            context: context
        )
        #expect(unavailable.image.size == full.image.size)
        #expect(unavailable.accessibilityValue == "Battery unavailable")

        let labeled = BatteryMenuBarPresenter.content(
            sample: sample,
            moduleSettings: ModuleSettings(isEnabled: true, mode: "labeledPercentage"),
            batterySettings: BatterySettings(),
            context: context
        )
        #expect(labeled.image.size.width > low.image.size.width)
        #expect(labeled.accessibilityValue == low.accessibilityValue)
    }

    @Test
    func timePresentationUsesCustomTokensAndReportsItsValue() {
        let sample = TimeSample(
            timestamp: Date(timeIntervalSince1970: 1_704_110_400),
            systemTimeZoneIdentifier: "UTC"
        )
        let content = TimeMenuBarPresenter.content(
            sample: sample,
            settings: ModuleSettings(isEnabled: true, mode: "custom"),
            timeSettings: TimeSettings(menuBarTemplate: "{time24} {zone}"),
            context: context
        )

        #expect(content.image.size.width > 0)
        #expect(content.accessibilityValue == "Time 13:20 UTC")
        let unavailable = TimeMenuBarPresenter.content(
            sample: nil,
            settings: ModuleSettings(isEnabled: true, mode: "custom"),
            timeSettings: TimeSettings(menuBarTemplate: "{time24} {zone}"),
            context: context
        )
        #expect(unavailable.image.size == content.image.size)
    }

    @Test
    func weatherRefreshAgeMakesSuccessfulUpdatesVisible() {
        let now = Date(timeIntervalSince1970: 10_000)

        #expect(
            WeatherDropdownView.updatedText(fetchedAt: now.addingTimeInterval(-12), now: now)
                == "Weather updated just now")
        #expect(
            WeatherDropdownView.updatedText(fetchedAt: now.addingTimeInterval(-125), now: now)
                == "Weather updated 2 min ago")
    }

    @Test
    func combinedCompositionUsesCompactGapsAndPreservesMemberVisibilitySettings() {
        let childContext = RenderContext(
            thickness: context.thickness,
            appearance: context.appearance,
            palette: context.palette,
            fontSize: context.fontSize,
            isMonochrome: context.isMonochrome,
            scale: context.scale
        )
        let images = [
            StackedLabelRenderer(label: "CPU", value: "42%").render(in: childContext),
            StackedLabelRenderer(label: "MEM", value: "68%").render(in: childContext),
        ]
        let compact = CombinedImageRenderer(images: images, showsSeparators: false).render(in: context)
        let separated = CombinedImageRenderer(images: images, showsSeparators: true).render(in: context)

        #expect(compact.size.width < separated.size.width)
        var settings = AppSettings()
        settings.modules[.combined]?.isEnabled = true
        settings.combined = CombinedSettings(members: [.cpu], hidesIndividualMembers: true)
        #expect(StatusItemRendering.isHiddenByCombined(module: .cpu, settings: settings))
        #expect(!StatusItemRendering.isHiddenByCombined(module: .memory, settings: settings))
        #expect(!StatusItemRendering.isHiddenByCombined(module: .combined, settings: settings))
    }

    @Test
    func samplingRunsOnlyForEnabledModulesAndCombinedDependencies() {
        var settings = AppSettings()
        settings.modules = Dictionary(
            uniqueKeysWithValues: ModuleID.allCases.map {
                ($0, ModuleSettings())
            })
        settings.modules[.gpu]?.isEnabled = true
        settings.modules[.gpu]?.mode = "combinedCPU"
        settings.modules[.combined]?.isEnabled = true
        settings.combined = CombinedSettings(members: [.memory, .weather])

        #expect(MonitoringCoordinator.modulesRequiringSamples(settings) == [.cpu, .gpu, .memory])
    }

    @Test
    func settingsNavigationTargetsTheRequestedWidget() {
        let navigation = SettingsNavigationModel()

        for module in ModuleID.allCases {
            navigation.open(module: module)
            #expect(navigation.selection == .module(module))
        }
        navigation.open(module: nil)
        #expect(navigation.selection == .general)
    }

    @Test
    func stackedRowsShareOneLeadingEdge() {
        let metrics = MenuBarLayoutMetrics(context: context)
        let origins = metrics.stackedOrigins(labelHeight: 10, valueHeight: 12)
        let rendererOrigins = StackedLabelRenderer.rowXOrigins

        #expect(origins.label.x == origins.value.x)
        #expect(origins.label.x == MenuBarLayoutMetrics.contentInset)
        #expect(rendererOrigins.label == rendererOrigins.value)
        #expect(rendererOrigins.label == MenuBarLayoutMetrics.contentInset)
        #expect(MenuBarLayoutMetrics.contentInset == 0)
        #expect(metrics.denseTextPadding == 0)
        #expect(origins.value.y == 1)
        #expect(origins.label.y == 13)
    }

    @Test
    func fixedWidthTextUsesNoAppAddedEdgePadding() {
        let text = "100%"
        let image = TextRenderer(text: "7%", reservedText: text).render(in: context)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: context.font(ofSize: context.fontSize, weight: .medium, monospacedDigits: true)
        ]
        let reservedWidth = NSAttributedString(string: text, attributes: attributes).size().width

        #expect(image.size.width == ceil(reservedWidth))
        #expect(TextRenderer.trailingOffset(valueWidth: 12, reservedWidth: 20) == 8)
    }

    @Test
    func statusItemSpacingOverrideUsesCompactApplicationValues() {
        let suiteName = "com.barometer.tests.status-item-spacing.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated defaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(4, forKey: StatusItemSpacingPolicy.spacingKey)
        defaults.set(4, forKey: StatusItemSpacingPolicy.selectionPaddingKey)

        StatusItemSpacingPolicy.apply(to: defaults)

        #expect(defaults.integer(forKey: StatusItemSpacingPolicy.spacingKey) == 1)
        #expect(defaults.integer(forKey: StatusItemSpacingPolicy.selectionPaddingKey) == 1)
    }

    @Test
    func iconMatchesFontSizeAndUsesCanonicalGap() {
        let metrics = MenuBarLayoutMetrics(context: context)
        let size = metrics.symbolSize(nativeSize: NSSize(width: 18, height: 12), font: NSFont.systemFont(ofSize: 12.65))

        #expect(abs(size.height - 14.5475) < 0.001)
        #expect(size.width == 22)
        #expect(metrics.iconTextGap == 4)
        #expect(metrics.centeredY(for: size.height) == 5)
        let symbolY = metrics.symbolY(
            for: size,
            nativeSize: NSSize(width: 18, height: 12),
            alignmentRect: NSRect(x: 0, y: 1, width: 18, height: 9)
        )
        #expect(abs(symbolY - 5.527) < 0.001)
    }

    @Test
    func stackedWeatherUsesTheCompactGridAndLessWidth() {
        let horizontal = IconTextRenderer(symbolName: "cloud.sun", text: "77°F").render(in: context)
        let stacked = IconStackRenderer(symbolName: "cloud.sun", text: "77°F").render(in: context)

        #expect(stacked.size.height == context.thickness)
        #expect(stacked.size.width < horizontal.size.width)
    }

    @Test
    func stackedRendererReservesTheWidestRowWithoutChangingAlignment() {
        let memory = StackedLabelRenderer(label: "MEM", value: "85%").render(in: context)
        let cpu = StackedLabelRenderer(label: "CPU", value: "24%").render(in: context)
        let idleGPU = StackedLabelRenderer(label: "GPU", value: "0%", reservedValue: "99%").render(in: context)
        let busyGPU = StackedLabelRenderer(label: "GPU", value: "99%", reservedValue: "99%").render(in: context)

        #expect(memory.size.height == context.thickness)
        #expect(cpu.size.height == context.thickness)
        #expect(memory.size.width > 0)
        #expect(cpu.size.width > 0)
        #expect(idleGPU.size == busyGPU.size)
    }

    @Test
    func iconRenderersReserveTextAndWeatherSymbolWidths() {
        let symbols = ["sun.max", "cloud.sun", "cloud.bolt.rain"]
        let horizontal = symbols.map { symbol in
            IconTextRenderer(
                symbolName: symbol,
                text: "7°F",
                reservedText: "99°F",
                reservedSymbolNames: symbols
            ).render(in: context)
        }
        let stacked = symbols.map { symbol in
            IconStackRenderer(
                symbolName: symbol,
                text: "7°F",
                reservedText: "99°F",
                reservedSymbolNames: symbols
            ).render(in: context)
        }

        #expect(Set(horizontal.map(\.size)).count == 1)
        #expect(Set(stacked.map(\.size)).count == 1)
    }

    @Test
    func helperProcessesUseTheirOwningApplicationIcon() {
        let discordHelper =
            "/Applications/Discord.app/Contents/Frameworks/"
            + "Discord Helper.app/Contents/MacOS/Discord Helper"
        let spotifyHelper =
            "/Applications/Spotify.app/Contents/Frameworks/"
            + "Spotify Helper.app/Contents/MacOS/Spotify Helper"

        #expect(ProcessIconResolver.applicationURL(for: discordHelper)?.path == "/Applications/Discord.app")
        #expect(ProcessIconResolver.applicationURL(for: spotifyHelper)?.path == "/Applications/Spotify.app")
        #expect(ProcessIconResolver.applicationURL(for: "/usr/bin/curl") == nil)
    }

    @Test
    func cpuAndMemoryPresentationsKeepOneWidthFromUnavailableThroughFullUse() {
        let cores = (0..<ProcessInfo.processInfo.activeProcessorCount).map {
            CPUCoreSample(index: $0, kind: .unknown, usagePercent: 100)
        }
        let cpu = CPUSample(
            timestamp: .now,
            totalPercent: 100,
            userPercent: 75,
            systemPercent: 25,
            idlePercent: 0,
            nicePercent: 0,
            perCore: cores,
            loadAverages: [1, 1, 1],
            uptime: 1,
            processCount: 1,
            threadCount: 1,
            topProcesses: []
        )
        let memory = MemorySample(
            timestamp: .now,
            total: 100,
            used: 100,
            app: 25,
            wired: 25,
            compressed: 25,
            cached: 0,
            free: 0,
            pressurePercent: 100,
            pressureLevel: .critical,
            swapUsed: 0,
            swapTotal: 0,
            topProcesses: []
        )

        for mode in ["percentage", "stacked", "iconText", "graph", "perCore"] {
            let settings = ModuleSettings(isEnabled: true, mode: mode)
            let unavailable = MonitoringCoordinator.renderCPU(
                sample: nil,
                history: [],
                settings: settings,
                context: context
            )
            let full = MonitoringCoordinator.renderCPU(
                sample: cpu,
                history: [HistoryEntry(timestamp: cpu.timestamp, value: cpu)],
                settings: settings,
                context: context
            )
            #expect(unavailable.image.size == full.image.size)
        }

        for mode in ["usedPercentage", "pressurePercentage", "stacked", "graph", "bar"] {
            let settings = ModuleSettings(isEnabled: true, mode: mode)
            let unavailable = MonitoringCoordinator.renderMemory(
                sample: nil,
                history: [],
                settings: settings,
                context: context
            )
            let full = MonitoringCoordinator.renderMemory(
                sample: memory,
                history: [HistoryEntry(timestamp: memory.timestamp, value: memory)],
                settings: settings,
                context: context
            )
            #expect(unavailable.image.size == full.image.size)
        }
    }

    @Test
    func graphicScaleDoesNotChangeTextSize() {
        let smallGraphics = RenderContext(
            thickness: context.thickness,
            appearance: context.appearance,
            palette: context.palette,
            fontSize: context.fontSize,
            isMonochrome: context.isMonochrome,
            scale: 0.75
        )
        let largeGraphics = RenderContext(
            thickness: context.thickness,
            appearance: context.appearance,
            palette: context.palette,
            fontSize: context.fontSize,
            isMonochrome: context.isMonochrome,
            scale: 1.15
        )

        let smallText = TextRenderer(text: "42%").render(in: smallGraphics)
        let largeText = TextRenderer(text: "42%").render(in: largeGraphics)
        let smallGraph = GraphRenderer(values: [0.2, 0.8], style: .line).render(in: smallGraphics)
        let largeGraph = GraphRenderer(values: [0.2, 0.8], style: .line).render(in: largeGraphics)

        #expect(smallText.size == largeText.size)
        #expect(smallGraph.size.width < largeGraph.size.width)
    }

    @Test
    func statusItemLengthMatchesRenderedCanvasWithoutAppKitInsets() {
        let image = TextRenderer(text: "CPU").render(in: context)
        let target = StatusItemRendering.itemLength(for: image)
        var latch = StatusItemLengthLatch()

        #expect(target == ceil(image.size.width))
        #expect(latch.resolve(target).shouldAssign)
        #expect(!latch.resolve(target).shouldAssign)
        #expect(!latch.resolve(target + 1).shouldAssign)
    }

    @Test
    func networkPresentationSupportsEveryMenuBarMode() {
        let interface = NetworkInterfaceSample(
            name: "en0",
            isUp: true,
            isLoopback: false,
            isVPN: false,
            ipv4Addresses: ["192.0.2.10"],
            ipv6Addresses: [],
            downloadBytesPerSecond: 1_250_000,
            uploadBytesPerSecond: 82_000,
            receivedBytes: 10_000_000,
            sentBytes: 2_000_000,
            inputErrors: 0,
            outputErrors: 0
        )
        let sample = NetworkSample(
            timestamp: Date(timeIntervalSince1970: 10),
            interfaces: [interface],
            primaryInterface: "en0",
            router: "192.0.2.1",
            dnsServers: ["192.0.2.53"],
            wifi: nil,
            publicIP: nil
        )
        let history = [HistoryEntry(timestamp: sample.timestamp, value: sample)]

        for mode in ["twoLine", "arrows", "stacked", "graph"] {
            let settings = ModuleSettings(isEnabled: true, mode: mode)
            let content = NetworkMenuBarPresenter.content(
                sample: sample,
                history: history,
                moduleSettings: settings,
                networkSettings: NetworkSettings(),
                context: context
            )
            let unavailable = NetworkMenuBarPresenter.content(
                sample: nil,
                history: [],
                moduleSettings: settings,
                networkSettings: NetworkSettings(),
                context: context
            )
            #expect(content.image.size.width > 0)
            #expect(content.accessibilityValue.contains("Network en0"))
            #expect(unavailable.image.size == content.image.size)
        }
    }

    @Test
    func peerRowsKeepTheSameGeometryWhenSwapped() {
        let first = NetworkRateStackRenderer(
            download: "1.2MB/s",
            upload: "82.0KB/s",
            reservedValue: "99.9GB/s"
        ).render(in: context)
        let swapped = NetworkRateStackRenderer(
            download: "82.0KB/s",
            upload: "1.2MB/s",
            reservedValue: "99.9GB/s"
        ).render(in: context)

        let threeDigitRate = NetworkRateStackRenderer(
            download: "125.0MB/s",
            upload: "1.2MB/s",
            reservedValue: "99.9GB/s"
        ).render(in: context)

        #expect(first.size == swapped.size)
        #expect(first.size.height == context.thickness)
        #expect(threeDigitRate.size.width > first.size.width)
    }

    @Test
    func compactNetworkRatesKeepOneReservedWidthAcrossUnitPromotion() {
        let placeholder = NetworkRateFormatter.compactPlaceholder(unit: .bytes, decimalPlaces: 2)
        let images = [99_994.0, 99_995.0, 125_000.0, 99_000_000.0].map { rate in
            let value = NetworkRateFormatter.compactString(
                bytesPerSecond: rate,
                unit: .bytes,
                decimalPlaces: 2
            )
            return NetworkRateStackRenderer(
                download: value,
                upload: value,
                reservedValue: placeholder
            ).render(in: context)
        }

        #expect(Set(images.map(\.size.width)).count == 1)
    }

    @Test
    func networkRowsKeepMarkersFixedAndValuesTrailingAligned() {
        #expect(NetworkRateStackRenderer.rowParts("↑1.2MB/s").marker == "↑")
        #expect(NetworkRateStackRenderer.rowParts("↑1.2MB/s").value == "1.2MB/s")

        let font = context.font(ofSize: 9, weight: .medium, monospacedDigits: true)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let shortWidth = NSAttributedString(string: "0.0KB/s", attributes: attributes).size().width
        let longWidth = NSAttributedString(string: "99.9MB/s", attributes: attributes).size().width
        let shortOrigin = NetworkRateStackRenderer.trailingOffset(
            valueWidth: shortWidth,
            reservedWidth: longWidth
        )
        let longOrigin = NetworkRateStackRenderer.trailingOffset(
            valueWidth: longWidth,
            reservedWidth: longWidth
        )

        #expect(abs((shortOrigin + shortWidth) - (longOrigin + longWidth)) < 0.01)
    }

    @Test
    func sensorStackKeepsStableGeometryAndExpandsByColumns() {
        #expect(SensorStackRenderer.displayLabel("CPU") == "CPU:")
        #expect(SensorStackRenderer.displayLabel("GPU:") == "GPU:")
        let topOrigins = SensorStackRenderer.rowOrigins(columnX: 3, columnWidth: 68, valueWidth: 34)
        let bottomOrigins = SensorStackRenderer.rowOrigins(columnX: 3, columnWidth: 68, valueWidth: 34)
        #expect(topOrigins.label == bottomOrigins.label)
        #expect(topOrigins.value == bottomOrigins.value)

        let cool = SensorStackRenderer(values: [
            SensorStackValue(label: "CPU", value: "39.1°C", reservedValue: "999.9°C"),
            SensorStackValue(label: "GPU", value: "41.2°C", reservedValue: "999.9°C"),
        ]).render(in: context)
        let hot = SensorStackRenderer(values: [
            SensorStackValue(label: "CPU", value: "102.4°C", reservedValue: "999.9°C"),
            SensorStackValue(label: "GPU", value: "99.9°C", reservedValue: "999.9°C"),
        ]).render(in: context)
        let fourReadings = SensorStackRenderer(values: [
            SensorStackValue(label: "CPU", value: "39.1°C", reservedValue: "999.9°C"),
            SensorStackValue(label: "GPU", value: "41.2°C", reservedValue: "999.9°C"),
            SensorStackValue(label: "SSD", value: "37.0°C", reservedValue: "999.9°C"),
            SensorStackValue(label: "FAN", value: "1400r", reservedValue: "9999r"),
        ]).render(in: context)

        #expect(cool.size == hot.size)
        #expect(cool.size.height == context.thickness)
        #expect(fourReadings.size.width > cool.size.width)
    }

    @Test
    func sessionEnergyUsesPlainLanguageUnits() {
        #expect(SensorsDropdownView.energy(125) == "125.0 joules")
        #expect(SensorsDropdownView.energy(7_200) == "2.000 watt-hours")
    }

    @Test
    func sensorsPresentationSupportsEveryWidgetMode() {
        let temperature = SensorReading(
            id: "derived:temperature:hottest",
            name: "Hottest",
            shortName: "HOT",
            rawName: "hottest",
            kind: .temperature,
            source: .derived,
            value: 54.25,
            unit: .celsius
        )
        let fan = SensorReading(
            id: "smc:fan:0",
            name: "Left Fan",
            shortName: "FAN1",
            rawName: "F0Ac",
            kind: .fan,
            source: .smc,
            value: 1_400,
            unit: .rpm
        )
        let sample = SensorSample(timestamp: .now, readings: [temperature, fan], sessionEnergy: [])
        let history = [HistoryEntry(timestamp: sample.timestamp, value: sample)]

        for mode in SensorWidgetMode.allCases {
            let widget = SensorWidgetSettings(id: 1, mode: mode)
            let content = SensorsMenuBarPresenter.content(
                sample: sample,
                history: history,
                moduleSettings: ModuleSettings(isEnabled: true, mode: mode.rawValue),
                sensorSettings: SensorSettings(),
                widget: widget,
                temperatureUnit: .celsius,
                context: context
            )
            #expect(content.image.size.width > 0)
            #expect(content.accessibilityValue.contains("Hottest"))
            let unavailable = SensorsMenuBarPresenter.content(
                sample: nil,
                history: [],
                moduleSettings: ModuleSettings(isEnabled: true, mode: mode.rawValue),
                sensorSettings: SensorSettings(),
                widget: widget,
                temperatureUnit: .celsius,
                context: context
            )
            #expect(unavailable.image.size == content.image.size)
        }
    }

    @Test
    func gpuPresentationSupportsEveryMenuBarMode() {
        let sample = GPUSample(
            timestamp: Date(timeIntervalSince1970: 10),
            name: "Test GPU",
            deviceUtilizationPercent: 42,
            rendererUtilizationPercent: 39,
            tilerUtilizationPercent: 17,
            memoryInUseBytes: 1_000,
            memoryAllocatedBytes: 2_000,
            frequencyMHz: 1_200,
            powerWatts: 3.5,
            temperatureCelsius: 52
        )
        let history = [HistoryEntry(timestamp: sample.timestamp, value: sample)]

        for mode in ["percentage", "graph", "combinedCPU"] {
            let settings = ModuleSettings(isEnabled: true, mode: mode)
            let content = GPUMenuBarPresenter.content(
                sample: sample,
                history: history,
                cpuPercent: 21,
                settings: settings,
                context: context
            )
            let unavailable = GPUMenuBarPresenter.content(
                sample: nil,
                history: [],
                cpuPercent: 21,
                settings: settings,
                context: context
            )
            #expect(content.image.size.width > 0)
            #expect(content.image.size.height == context.thickness)
            #expect(content.accessibilityValue == "GPU 42.0 percent")
            #expect(unavailable.image.size == content.image.size)
        }
    }

    @Test
    func diskPresentationSupportsEveryMenuBarMode() {
        let volume = DiskVolumeSample(
            id: "startup",
            name: "Macintosh HD",
            mountPoint: "/",
            bsdName: "disk3s3s1",
            physicalBSDName: "disk0",
            totalBytes: 1_000,
            usedBytes: 650,
            availableBytes: 350,
            kind: .internalDisk,
            isEjectable: false,
            isRemovable: false,
            isReadOnly: true
        )
        let device = DiskDeviceSample(
            bsdName: "disk0",
            model: "Test SSD",
            readBytesPerSecond: 1_250_000,
            writeBytesPerSecond: 82_000,
            readOperationsPerSecond: 20,
            writeOperationsPerSecond: 5,
            bytesRead: 10_000_000,
            bytesWritten: 2_000_000,
            readOperations: 100,
            writeOperations: 50,
            readErrors: 0,
            writeErrors: 0
        )
        let sample = DiskSample(
            timestamp: Date(timeIntervalSince1970: 10),
            volumes: [volume],
            devices: [device]
        )
        let history = [HistoryEntry(timestamp: sample.timestamp, value: sample)]

        for mode in ["activityGraph", "freePercentage", "freeBytes", "rates"] {
            let settings = ModuleSettings(isEnabled: true, mode: mode)
            let content = DiskMenuBarPresenter.content(
                sample: sample,
                history: history,
                moduleSettings: settings,
                diskSettings: DiskSettings(),
                context: context
            )
            let unavailable = DiskMenuBarPresenter.content(
                sample: nil,
                history: [],
                moduleSettings: settings,
                diskSettings: DiskSettings(),
                context: context
            )
            #expect(content.image.size.width > 0)
            #expect(content.accessibilityValue.contains("Disks read"))
            #expect(unavailable.image.size == content.image.size)
        }
    }
}

@MainActor
struct MenuBarSizingTests {
    private func context(thickness: CGFloat, fontSize: CGFloat, scale: CGFloat = 1.15) -> RenderContext {
        RenderContext(
            thickness: thickness,
            appearance: .dark,
            palette: MenuBarPalette(light: .black, dark: .white),
            fontSize: fontSize,
            isMonochrome: true,
            scale: scale
        )
    }

    @Test
    func defaultFontSizeKeepsTheOriginalCompactGrid() {
        #expect(MenuBarLayoutMetrics(context: context(thickness: 22, fontSize: 12)).compactPointSize == 9)
        #expect(MenuBarLayoutMetrics(context: context(thickness: 24, fontSize: 12)).compactPointSize == 10)
    }

    @Test
    func fontSizeSliderMovesTwoRowTextAcrossItsRange() {
        let sizes = stride(
            from: AppSettings.menuBarFontSizeRange.lowerBound,
            through: AppSettings.menuBarFontSizeRange.upperBound,
            by: 0.5
        ).map {
            MenuBarLayoutMetrics(context: context(thickness: 22, fontSize: $0)).compactPointSize
        }
        #expect(sizes.first == 8)
        #expect(sizes.last == 9)
        #expect(sizes == sizes.sorted())
        #expect(Set(sizes).count >= 3)
        #expect(MenuBarLayoutMetrics.maximumCompactPointSize(thickness: 22) == 11)
        #expect(MenuBarLayoutMetrics.maximumCompactPointSize(thickness: 24) == 12.5)
        #expect(sizes.allSatisfy { $0 <= MenuBarLayoutMetrics.maximumCompactPointSize(thickness: 22) })
    }

    @Test
    func largerFontWidensTwoRowItemsButNeverChangesTheirHeight() {
        let small = StackedLabelRenderer(label: "CPU", value: "42%", reservedValue: "100%")
            .render(in: context(thickness: 22, fontSize: 9))
        let large = StackedLabelRenderer(label: "CPU", value: "42%", reservedValue: "100%")
            .render(in: context(thickness: 22, fontSize: 12))
        #expect(large.size.width > small.size.width)
        #expect(small.size.height == 22)
        #expect(large.size.height == 22)
    }

    @Test
    func iconScaleResizesCompactSymbolsAndGraphs() {
        let native = NSSize(width: 20, height: 16)
        let small = MenuBarLayoutMetrics(context: context(thickness: 22, fontSize: 12, scale: 0.75))
        let maximum = MenuBarLayoutMetrics(context: context(thickness: 22, fontSize: 12, scale: 1.15))

        #expect(maximum.compactSymbolVisibleHeight == 10)
        #expect(small.compactSymbolVisibleHeight < maximum.compactSymbolVisibleHeight)
        let padded = NSRect(x: 2, y: 3, width: 16, height: 10)
        #expect(maximum.compactSymbolSize(nativeSize: native, alignmentRect: padded).height == 16)
        #expect(maximum.compactSymbolSize(nativeSize: native).height == 10)

        #expect(maximum.graphVerticalInset(default: 3) == 3)
        #expect(small.graphVerticalInset(default: 3) > maximum.graphVerticalInset(default: 3))

        let narrow = GraphRenderer(values: [0.2, 0.6, 0.4], style: .area)
            .render(in: context(thickness: 22, fontSize: 12, scale: 0.75))
        let wide = GraphRenderer(values: [0.2, 0.6, 0.4], style: .area)
            .render(in: context(thickness: 22, fontSize: 12, scale: 1.15))
        #expect(wide.size.width > narrow.size.width)
        #expect(wide.size.height == 22)
    }
}

@MainActor
struct StableCanvasTests {
    private let context = RenderContext(
        thickness: 22,
        appearance: .dark,
        palette: MenuBarPalette(light: .black, dark: .white),
        fontSize: 12,
        isMonochrome: true,
        scale: 1.15,
        fontWeight: .semibold
    )

    private func reading(id: String, name: String, shortName: String, value: Double, kind: SensorKind = .temperature)
        -> SensorReading
    {
        SensorReading(
            id: id,
            name: name,
            shortName: shortName,
            rawName: id,
            kind: kind,
            source: .derived,
            value: value,
            unit: kind == .fan ? .rpm : .celsius
        )
    }

    private func sensorsWidth(sample: SensorSample?) -> CGFloat {
        var widget = SensorWidgetSettings(id: 1)
        widget.sensorIDs = ["derived:temperature:cpu", "derived:temperature:gpu"]
        widget.mode = .compactStack
        return SensorsMenuBarPresenter.content(
            sample: sample,
            history: [],
            moduleSettings: ModuleSettings(mode: "compactStack", interval: 5),
            sensorSettings: SensorSettings(),
            widget: widget,
            temperatureUnit: .celsius,
            context: context
        ).image.size.width
    }

    @Test
    func sensorsCanvasIsIdenticalBeforeDuringAndAfterDiscovery() {
        let cpu = reading(id: "derived:temperature:cpu", name: "CPU Temperature", shortName: "CPU", value: 45.6)
        let gpu = reading(id: "derived:temperature:gpu", name: "GPU Temperature", shortName: "GPU", value: 54.0)
        let unavailable = sensorsWidth(sample: nil)
        let partial = sensorsWidth(sample: SensorSample(timestamp: Date(), readings: [cpu], sessionEnergy: []))
        let live = sensorsWidth(sample: SensorSample(timestamp: Date(), readings: [cpu, gpu], sessionEnergy: []))
        let hot = sensorsWidth(
            sample: SensorSample(
                timestamp: Date(),
                readings: [
                    reading(id: "derived:temperature:cpu", name: "CPU Temperature", shortName: "CPU", value: 109.9),
                    reading(id: "derived:temperature:gpu", name: "GPU Temperature", shortName: "GPU", value: 99.9),
                ], sessionEnergy: []))
        #expect(unavailable == partial)
        #expect(partial == live)
        #expect(live == hot)
    }

    @Test
    func stackedWeatherWidthDoesNotFollowTheConditionGlyph() {
        let widths = ["cloud", "cloud.sun.rain", "sun.max", "cloud.bolt.rain", "wind"].map { symbol in
            IconStackRenderer(symbolName: symbol, text: "70°F", reservedText: "99°F").render(in: context).size.width
        }
        #expect(Set(widths).count == 1)
    }
}

@MainActor
struct StableGeometryTests {
    @Test
    func registryPreparesOnlyLaunchVisibleIdentitiesInModuleOrder() {
        var settings = AppSettings()
        for module in ModuleID.allCases {
            settings.modules[module]?.isEnabled = false
        }
        for module in [ModuleID.cpu, .gpu, .network, .sensors, .weather] {
            settings.modules[module]?.isEnabled = true
        }
        settings.sensors.widgets = [SensorWidgetSettings(id: 1), SensorWidgetSettings(id: 2)]

        #expect(
            StatusItemRegistry.launchIdentities(settings: settings).map(\.autosaveName) == [
                "Barometer.CPU",
                "Barometer.GPU",
                "Barometer.Network",
                "Barometer.Sensors",
                "Barometer.Sensors.2",
                "Barometer.Weather",
            ]
        )

        settings.modules[.combined]?.isEnabled = true
        settings.combined.hidesIndividualMembers = true
        settings.combined.members = [.gpu, .weather]
        #expect(
            StatusItemRegistry.launchIdentities(settings: settings).map(\.autosaveName) == [
                "Barometer.CPU",
                "Barometer.Network",
                "Barometer.Sensors",
                "Barometer.Sensors.2",
                "Barometer.Combined",
            ]
        )
    }

    @Test
    func widthsRoundToTheTwoPointGrid() {
        #expect(StatusItemRendering.roundedLength(29) == 30)
        #expect(StatusItemRendering.roundedLength(32) == 32)
        #expect(StatusItemRendering.roundedLength(1) == 2)
    }

    @Test
    func liveLengthLatchRejectsEveryLaterWidthProposal() {
        var latch = StatusItemLengthLatch()
        let initial = latch.resolve(32)
        let wider = latch.resolve(40)
        let narrower = latch.resolve(20)

        #expect(initial.length == 32)
        #expect(initial.shouldAssign)
        #expect(wider.length == 32)
        #expect(!wider.shouldAssign)
        #expect(narrower.length == 32)
        #expect(!narrower.shouldAssign)
        #expect(latch.length == 32)
        #expect(StatusItemRendering.roundedLength(33) == 34)

        let narrowContext = RenderContext(
            thickness: 22,
            appearance: .dark,
            palette: MenuBarPalette(light: .black, dark: .white),
            fontSize: 12,
            isMonochrome: true,
            scale: 0.75
        )
        let wideContext = RenderContext(
            thickness: 22,
            appearance: .dark,
            palette: MenuBarPalette(light: .black, dark: .white),
            fontSize: 12,
            isMonochrome: true,
            scale: 1.15
        )
        let renderer = GraphRenderer(values: [0.2, 0.8, 0.4], style: .line)
        let applied = StatusItemRendering.roundedLength(renderer.render(in: narrowContext).size.width)
        let staged = StatusItemRendering.roundedLength(renderer.render(in: wideContext).size.width)
        #expect(staged > applied)
        var renderedWidth = StatusItemLengthLatch()
        #expect(renderedWidth.resolve(applied).shouldAssign)
        #expect(renderedWidth.resolve(staged).length == applied)
    }

    @Test
    func geometryLatchRejectsEveryLaterSizeProposal() {
        var latch = StatusItemGeometryLatch()
        let initial = StatusItemGeometry(fontSize: 12, scale: 1.15)
        let compact = StatusItemGeometry(fontSize: 9, scale: 0.75)

        #expect(latch.resolve(initial) == initial)
        #expect(latch.resolve(compact) == initial)
        #expect(latch.geometry == initial)
    }

    @Test
    func visibilityLatchActivatesExactlyOnce() {
        var latch = StatusItemVisibilityLatch()
        #expect(!latch.isActivated)
        let firstActivation = latch.activate()
        #expect(firstActivation)
        #expect(latch.isActivated)
        let secondActivation = latch.activate()
        #expect(!secondActivation)
    }

    @Test
    func framedImagesKeepFullScaleCanvasHeightAndTemplateFlag() {
        let image = NSImage(size: NSSize(width: 29, height: 22), flipped: false) { _ in true }
        image.isTemplate = true
        let padded = StatusItemRendering.image(image, framedTo: 32)
        #expect(padded.size == NSSize(width: 32, height: 22))
        #expect(padded.isTemplate)
        let clipped = StatusItemRendering.image(image, framedTo: 24)
        #expect(clipped.size == NSSize(width: 24, height: 22))
        #expect(StatusItemRendering.image(image, framedTo: 29) === image)
    }

}
