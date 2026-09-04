import AppKit
import MenuBarStatsCore
import SystemSources
@testable import MenuBarStatsUI
import Testing

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
    }

    @Test
    func weatherRefreshAgeMakesSuccessfulUpdatesVisible() {
        let now = Date(timeIntervalSince1970: 10_000)

        #expect(WeatherDropdownView.updatedText(fetchedAt: now.addingTimeInterval(-12), now: now)
            == "Weather updated just now")
        #expect(WeatherDropdownView.updatedText(fetchedAt: now.addingTimeInterval(-125), now: now)
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
            scale: context.scale,
            horizontalSpacing: 0
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
        settings.modules = Dictionary(uniqueKeysWithValues: ModuleID.allCases.map {
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

        #expect(origins.label.x == origins.value.x)
        #expect(origins.label.x == MenuBarLayoutMetrics.contentInset)
        #expect(origins.value.y == 1)
        #expect(origins.label.y == 13)
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
    func horizontalSpacingChangesImageWidthByExactlyTwoInsets() {
        let compact = TextRenderer(text: "42%").render(in: context)
        let spacedContext = RenderContext(
            thickness: context.thickness,
            appearance: context.appearance,
            palette: context.palette,
            fontSize: context.fontSize,
            isMonochrome: context.isMonochrome,
            scale: context.scale,
            horizontalSpacing: 3
        )
        let spaced = TextRenderer(text: "42%").render(in: spacedContext)

        #expect(spaced.size.width == compact.size.width + 6)
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
            scale: 1.35
        )

        let smallText = TextRenderer(text: "42%").render(in: smallGraphics)
        let largeText = TextRenderer(text: "42%").render(in: largeGraphics)
        let smallGraph = GraphRenderer(values: [0.2, 0.8], style: .line).render(in: smallGraphics)
        let largeGraph = GraphRenderer(values: [0.2, 0.8], style: .line).render(in: largeGraphics)

        #expect(smallText.size == largeText.size)
        #expect(smallGraph.size.width < largeGraph.size.width)
    }

    @Test
    func compactLayoutReducesEligibleInternalGeometry() {
        let regular = RenderContext(
            thickness: context.thickness,
            appearance: context.appearance,
            palette: context.palette,
            fontSize: context.fontSize,
            isMonochrome: context.isMonochrome,
            scale: context.scale,
            usesCompactLayout: false
        )
        let compact = RenderContext(
            thickness: context.thickness,
            appearance: context.appearance,
            palette: context.palette,
            fontSize: context.fontSize,
            isMonochrome: context.isMonochrome,
            scale: context.scale,
            usesCompactLayout: true
        )

        #expect(IconTextRenderer(symbolName: "cloud", text: "77°F").render(in: compact).size.width
            < IconTextRenderer(symbolName: "cloud", text: "77°F").render(in: regular).size.width)
        #expect(GraphRenderer(values: [0.2, 0.8], style: .line).render(in: compact).size.width
            < GraphRenderer(values: [0.2, 0.8], style: .line).render(in: regular).size.width)
    }

    @Test
    func statusItemLengthMatchesRenderedCanvasWithoutAppKitInsets() {
        let image = TextRenderer(text: "CPU").render(in: context)
        let target = StatusItemRendering.itemLength(for: image)

        #expect(target == ceil(image.size.width))
        #expect(!StatusItemRendering.shouldUpdateLength(current: target, target: target))
        #expect(StatusItemRendering.shouldUpdateLength(current: nil, target: target))
        #expect(StatusItemRendering.shouldUpdateLength(current: target + 1, target: target))
    }

    @Test
    func hiddenStatusItemsRemoveOnlyVisibilityPreferences() {
        #expect(StatusItemRendering.visibilityPreferenceKeys(autosaveName: "Barometer.Disks") == [
            "NSStatusItem VisibleCC Barometer.Disks",
            "NSStatusItem Visible Barometer.Disks",
        ])
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
            let content = NetworkMenuBarPresenter.content(
                sample: sample,
                history: history,
                moduleSettings: ModuleSettings(isEnabled: true, mode: mode),
                networkSettings: NetworkSettings(),
                context: context
            )
            #expect(content.image.size.width > 0)
            #expect(content.accessibilityValue.contains("Network en0"))
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
    func sensorStackKeepsStableGeometryAndExpandsByColumns() {
        #expect(SensorStackRenderer.displayLabel("CPU") == "CPU:")
        #expect(SensorStackRenderer.displayLabel("GPU:") == "GPU:")

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
            let content = GPUMenuBarPresenter.content(
                sample: sample,
                history: history,
                cpuPercent: 21,
                settings: ModuleSettings(isEnabled: true, mode: mode),
                context: context
            )
            #expect(content.image.size.width > 0)
            #expect(content.image.size.height == context.thickness)
            #expect(content.accessibilityValue == "GPU 42.0 percent")
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
            let content = DiskMenuBarPresenter.content(
                sample: sample,
                history: history,
                moduleSettings: ModuleSettings(isEnabled: true, mode: mode),
                diskSettings: DiskSettings(),
                context: context
            )
            #expect(content.image.size.width > 0)
            #expect(content.accessibilityValue.contains("Disks read"))
        }
    }
}
