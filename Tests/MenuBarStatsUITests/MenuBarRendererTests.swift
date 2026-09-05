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
        #expect(labeled.image.size.width > 0)
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
        let date = sample.timestamp
        let zone = TimeZone(identifier: sample.systemTimeZoneIdentifier) ?? .current
        let abbreviation = zone.abbreviation(for: date) ?? zone.identifier
        #expect(content.accessibilityValue == "Time 12:00 \(abbreviation)")
        let unavailable = TimeMenuBarPresenter.content(
            sample: nil,
            settings: ModuleSettings(isEnabled: true, mode: "custom"),
            timeSettings: TimeSettings(menuBarTemplate: "{time24} {zone}"),
            context: context
        )
        #expect(unavailable.image.size == content.image.size)
    }

    @Test("seconds clock fits the canvas calculated after relaunch")
    func secondsClockFitsRelaunchedCanvas() {
        let settings = ModuleSettings(isEnabled: true, mode: "custom", usesFixedWidth: true)
        let timeSettings = TimeSettings(menuBarTemplate: "{weekday} {time} {zone}", showsSeconds: true)
        let unavailable = TimeMenuBarPresenter.content(
            sample: nil,
            settings: settings,
            timeSettings: timeSettings,
            context: context
        )
        let dates = [
            Date(timeIntervalSince1970: 1_704_110_400),
            Date(timeIntervalSince1970: 1_704_153_599),
            Date(timeIntervalSince1970: 1_720_056_599),
        ]

        for date in dates {
            let content = TimeMenuBarPresenter.content(
                sample: TimeSample(timestamp: date, systemTimeZoneIdentifier: "America/New_York"),
                settings: settings,
                timeSettings: timeSettings,
                context: context
            )
            #expect(content.image.size.width <= unavailable.image.size.width)
            #expect(StatusItemRendering.roundedLength(content.image.size.width)
                <= StatusItemRendering.roundedLength(unavailable.image.size.width))
        }
    }

    @Test
    func weatherRefreshAgeMakesSuccessfulUpdatesVisible() {
        let now = Date(timeIntervalSince1970: 10_000)
        let timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let recent = WeatherDropdownView.updatedText(
            fetchedAt: now.addingTimeInterval(-12),
            now: now,
            timeZone: timeZone
        )
        let older = WeatherDropdownView.updatedText(
            fetchedAt: now.addingTimeInterval(-125),
            now: now,
            timeZone: timeZone
        )
        let crossedTwoClockMinutes = WeatherDropdownView.updatedText(
            fetchedAt: Date(timeIntervalSince1970: 7_259),
            now: Date(timeIntervalSince1970: 7_320),
            timeZone: timeZone
        )

        #expect(recent.hasPrefix("Updated "))
        #expect(recent.hasSuffix(" · just now"))
        #expect(older.hasPrefix("Updated "))
        #expect(older.hasSuffix(" · 2 min ago"))
        #expect(crossedTwoClockMinutes.hasSuffix(" · 2 min ago"))
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
        // A stack, not Combined membership, decides whether a module's own item is replaced.
        var settings = AppSettings()
        settings.modules[.combined]?.isEnabled = true
        settings.stacks = StacksSettings(stacks: [
            StackSettings(id: 1, metrics: [.cpuTotal], hidesSourceItems: true)
        ])
        #expect(StatusItemRendering.isHiddenByCombined(module: .cpu, settings: settings))
        #expect(!StatusItemRendering.isHiddenByCombined(module: .memory, settings: settings))
        #expect(!StatusItemRendering.isHiddenByCombined(module: .combined, settings: settings))

        // A stack that does not replace its sources leaves every individual item alone.
        settings.stacks.stacks[0].hidesSourceItems = false
        #expect(!StatusItemRendering.isHiddenByCombined(module: .cpu, settings: settings))

        // The stacks master switch overrides any individual stack.
        settings.stacks.stacks[0].hidesSourceItems = true
        settings.modules[.combined]?.isEnabled = false
        #expect(!StatusItemRendering.isHiddenByCombined(module: .cpu, settings: settings))
    }

    @Test
    func samplingRunsOnlyForEnabledModulesAndStackSources() {
        var settings = AppSettings()
        settings.modules = Dictionary(
            uniqueKeysWithValues: ModuleID.allCases.map {
                ($0, ModuleSettings())
            })
        settings.modules[.gpu]?.isEnabled = true
        settings.modules[.gpu]?.mode = "combinedCPU"
        settings.modules[.combined]?.isEnabled = true
        // A stack keeps its source modules sampling even though their own items are not enabled.
        // Weather is excluded because it refreshes on its own schedule rather than the samplers.
        settings.stacks = StacksSettings(stacks: [
            StackSettings(id: 1, metrics: [.memoryUsedPercent, .weatherTemperature])
        ])

        #expect(MonitoringCoordinator.modulesRequiringSamples(settings) == [.cpu, .gpu, .memory])

        // A disabled stack asks for nothing.
        settings.stacks.stacks[0].isEnabled = false
        #expect(MonitoringCoordinator.modulesRequiringSamples(settings) == [.cpu, .gpu])
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
        // Live content is centered in the reserved canvas, so the hover highlight sits over it
        // rather than beside it.
        #expect(TextRenderer.centeringOffset(contentWidth: 12, canvasWidth: 20) == 4)
        #expect(TextRenderer.centeringOffset(contentWidth: 20, canvasWidth: 20) == 0)
        #expect(TextRenderer.centeringOffset(contentWidth: 24, canvasWidth: 20) == 0)
    }

    @Test
    func statusItemSpacingPolicyRemovesLegacyApplicationOverrides() {
        let suiteName = "com.barometer.tests.status-item-spacing.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated defaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(4, forKey: StatusItemSpacingPolicy.spacingKey)
        defaults.set(4, forKey: StatusItemSpacingPolicy.selectionPaddingKey)

        StatusItemSpacingPolicy.restoreSystemDefault(in: defaults)

        let applicationDomain = defaults.persistentDomain(forName: suiteName)
        #expect(applicationDomain?[StatusItemSpacingPolicy.spacingKey] == nil)
        #expect(applicationDomain?[StatusItemSpacingPolicy.selectionPaddingKey] == nil)
    }

    @Test
    func iconMatchesFontSizeAndUsesCanonicalGap() {
        let metrics = MenuBarLayoutMetrics(context: context)
        let size = metrics.symbolSize(nativeSize: NSSize(width: 18, height: 12), font: NSFont.systemFont(ofSize: 12.65))

        #expect(abs(size.height - 14.5475) < 0.001)
        #expect(size.width == 22)
        #expect(metrics.iconTextGap == 4)
        let centeredY = metrics.centeredY(for: size.height)
        #expect(centeredY >= 0)
        #expect(centeredY.rounded(.down) == centeredY)
        #expect(centeredY + size.height <= context.thickness)
        let symbolY = metrics.symbolY(
            for: size,
            nativeSize: NSSize(width: 18, height: 12),
            alignmentRect: NSRect(x: 0, y: 1, width: 18, height: 9)
        )
        #expect(symbolY > centeredY)
        #expect(symbolY < centeredY + 1)
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
    func processIconsUseSmallSharedThumbnails() {
        let first = ProcessIconResolver.image(processIdentifier: 1, path: "/usr/bin/true")
        let second = ProcessIconResolver.image(processIdentifier: 2, path: "/usr/bin/true")
        #expect(first === second)
        #expect(first.size == NSSize(width: 16, height: 16))
        #expect(first.representations.count == 1)
        #expect(first.representations.first?.pixelsWide == 32)
        #expect(first.representations.first?.pixelsHigh == 32)
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
                history: [HistoryEntry(timestamp: cpu.timestamp, value: cpu.graphValue)],
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
                history: [HistoryEntry(timestamp: memory.timestamp, value: memory.graphValue)],
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
        let history = [HistoryEntry(timestamp: sample.timestamp, value: sample.graphValue)]

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
    func networkNameDistinguishesPermissionFromAnUnavailableSSID() {
        #expect(NetworkDropdownView.networkName(ssid: "Office", access: .authorized) == "Office")
        #expect(NetworkDropdownView.networkName(ssid: nil, access: .notDetermined) == "Location access required")
        #expect(NetworkDropdownView.networkName(ssid: nil, access: .authorized) == "Name unavailable")
        #expect(NetworkDropdownView.networkName(ssid: nil, access: .denied) == "Location access is off")
        #expect(NetworkDropdownView.locationActionTitle(for: .authorized) == "Retry")
    }

    @Test
    func networkInterfacePickerOffersActivePhysicalAndVPNInterfaces() {
        func interface(_ name: String, isUp: Bool = true, isLoopback: Bool = false) -> NetworkInterfaceSample {
            NetworkInterfaceSample(
                name: name,
                isUp: isUp,
                isLoopback: isLoopback,
                isVPN: name.hasPrefix("utun"),
                ipv4Addresses: [],
                ipv6Addresses: [],
                downloadBytesPerSecond: 0,
                uploadBytesPerSecond: 0,
                receivedBytes: 0,
                sentBytes: 0,
                inputErrors: 0,
                outputErrors: 0
            )
        }
        let sample = NetworkSample(
            timestamp: .now,
            interfaces: [
                interface("utun3"),
                interface("lo0", isLoopback: true),
                interface("en7", isUp: false),
                interface("en0"),
            ],
            primaryInterface: "en0",
            router: nil,
            dnsServers: [],
            wifi: nil,
            publicIP: nil
        )

        #expect(NetworkDropdownView.selectableInterfaces(sample).map(\.name) == ["en0", "utun3"])
    }

    @Test
    func cpuHistoryRangesMapToDistinctWindows() {
        #expect(HistoryRange.oneMinute.duration == 60)
        #expect(HistoryRange.fiveMinutes.duration == 300)
        #expect(HistoryRange.thirtyMinutes.duration == 1_800)
        #expect(HistoryRange.threeHours.duration == 10_800)
        #expect(HistoryRange.twentyFourHours.duration == 86_400)
    }

    @Test
    func cpuHistoryAlwaysUsesTheFullChartWidth() throws {
        let values = [0.2, 0.4, 0.8]
        let size = CGSize(width: 300, height: 84)
        let first = try #require(NormalizedGraphGeometry.point(
            at: 0,
            values: values,
            size: size,
            horizontalInset: 4,
            verticalInset: 3
        ))
        let last = try #require(NormalizedGraphGeometry.point(
            at: values.count - 1,
            values: values,
            size: size,
            horizontalInset: 4,
            verticalInset: 3
        ))
        #expect(first.x == 4)
        #expect(last.x == 296)
    }

    @Test
    func timelineGraphPositionsRecentDataWithinTheSelectedWindow() throws {
        let end = Date(timeIntervalSince1970: 1_000)
        let entries = [
            HistoryEntry(timestamp: end.addingTimeInterval(-60), value: CPUHistoryValue(totalPercent: 20)),
            HistoryEntry(timestamp: end, value: CPUHistoryValue(totalPercent: 80)),
        ]
        let fiveMinutes = TimelineGraphData.make(
            entries: entries,
            endingAt: end,
            duration: HistoryRange.fiveMinutes.duration,
            value: { $0.totalPercent / 100 }
        )
        let oneMinute = TimelineGraphData.make(
            entries: entries,
            endingAt: end,
            duration: HistoryRange.oneMinute.duration,
            value: { $0.totalPercent / 100 }
        )

        #expect(fiveMinutes.xPositions == [0.8, 1])
        #expect(oneMinute.xPositions == [0, 1])
        let fiveMinuteStart = try #require(NormalizedGraphGeometry.point(
            at: 0,
            values: fiveMinutes.values,
            xPositions: fiveMinutes.xPositions,
            size: CGSize(width: 300, height: 84),
            horizontalInset: 4,
            verticalInset: 3
        ))
        #expect(abs(fiveMinuteStart.x - 237.6) < 0.001)
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
    func networkRowsKeepMarkersAndValueOriginsFixed() {
        #expect(NetworkRateStackRenderer.rowParts("↑1.2MB/s").marker == "↑")
        #expect(NetworkRateStackRenderer.rowParts("↑1.2MB/s").value == "1.2MB/s")

        let shortOrigins = NetworkRateStackRenderer.rowOrigins(
            markerFieldWidth: 8,
            gap: 3,
            backingScaleFactor: 2
        )
        let longOrigins = NetworkRateStackRenderer.rowOrigins(
            markerFieldWidth: 8,
            gap: 3,
            backingScaleFactor: 2
        )
        #expect(shortOrigins.marker == 0)
        #expect(shortOrigins.value == 11)
        #expect(longOrigins == shortOrigins)

        let fractionalMarker = NetworkRateStackRenderer.rowOrigins(
            markerFieldWidth: 8.2,
            gap: 3,
            backingScaleFactor: 2
        )
        #expect(fractionalMarker.marker == 0)
        #expect(fractionalMarker.value == 11.5)
        #expect(fractionalMarker.value - 8.2 >= 3)
    }

    @Test
    func sensorStackKeepsStableGeometryAndExpandsByColumns() {
        #expect(MenuBarLayoutMetrics(context: context).oneDevicePixel == 0.5)
        #expect(MenuBarLayoutMetrics(context: context).sensorColumnGap == 0.5)
        #expect(MenuBarLayoutMetrics(context: context).densePairGap == 3)
        #expect(SensorStackRenderer.displayLabel("CPU") == "CPU:")
        #expect(SensorStackRenderer.displayLabel("GPU:") == "GPU:")
        let topOrigins = SensorStackRenderer.rowOrigins(
            columnX: 3,
            columnWidth: 71,
            labelWidth: 22,
            valueWidth: 34,
            gap: 3,
            backingScaleFactor: 2
        )
        let bottomOrigins = SensorStackRenderer.rowOrigins(
            columnX: 3,
            columnWidth: 71,
            labelWidth: 22,
            valueWidth: 34,
            gap: 3,
            backingScaleFactor: 2
        )
        #expect(topOrigins == bottomOrigins)
        #expect(topOrigins.label == 9)
        #expect(topOrigins.value == 34)
        #expect(topOrigins.value - topOrigins.label == 25)

        let fractionalLabel = SensorStackRenderer.rowOrigins(
            columnX: 3,
            columnWidth: 71,
            labelWidth: 22.2,
            valueWidth: 34,
            gap: 3,
            backingScaleFactor: 2
        )
        #expect(fractionalLabel.value - (fractionalLabel.label + 22.2) >= 3)

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
        let history = [HistoryEntry(timestamp: sample.timestamp, value: sample.graphValue)]

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
        let history = [HistoryEntry(timestamp: sample.timestamp, value: sample.graphValue)]

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
        let history = [HistoryEntry(timestamp: sample.timestamp, value: sample.graphValue)]

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

    @Test("every battery glyph the menu bar can show resolves on this system")
    func batterySymbolsResolve() {
        // SF Symbols publishes a bolt overlay only for the full glyph. A name that does not resolve
        // renders nothing and collapses the icon gap, changing the item's width.
        #expect(BatteryMenuBarPresenter.everyReservedSymbolResolves)
        for charge in [0.0, 20, 40, 65, 90, 100] {
            for charging in [false, true] {
                let name = BatteryMenuBarPresenter.symbolName(for: batterySample(charge: charge, charging: charging))
                #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "\(name) is missing")
            }
        }
    }

    @Test("every battery presentation holds one width, and they all share it")
    func batteryPresentationsHoldOneWidth() {
        var widthsAcrossModes: Set<Double> = []
        for mode in BatteryMenuBarPresenter.modes {
            var widths: Set<Double> = [
                BatteryMenuBarPresenter.content(
                    sample: nil,
                    moduleSettings: ModuleSettings(mode: mode),
                    batterySettings: BatterySettings(),
                    context: context
                ).image.size.width
            ]
            let cases: [(Double, Int?, Bool)] = [
                (0, nil, false), (5, 3, false), (50, 95, false), (82, 541, false),
                (100, 1_439, false), (7, 725, true), (99, 1, true), (100, nil, true),
            ]
            for (charge, minutes, charging) in cases {
                widths.insert(
                    BatteryMenuBarPresenter.content(
                        sample: batterySample(charge: charge, charging: charging, minutes: minutes),
                        moduleSettings: ModuleSettings(mode: mode),
                        batterySettings: BatterySettings(),
                        context: context
                    ).image.size.width
                )
            }
            #expect(widths.count == 1, "\(mode) produced widths \(widths.sorted())")
            widthsAcrossModes.formUnion(widths)
        }
        // Switching presentation must not resize the item: a status item keeps one length for the
        // life of the process, so a narrower mode would be squeezed and the item would move.
        #expect(widthsAcrossModes.count == 1, "modes produced widths \(widthsAcrossModes.sorted())")
    }

    @Test("a stack column holds one width while its readings move")
    func stackColumnsHoldOneWidth() {
        var widths: Set<Double> = []
        for value in ["0%", "7%", "100%", "—"] {
            for time in ["0:00", "9:01", "12:05", "—"] {
                widths.insert(
                    SensorStackRenderer(values: [
                        SensorStackValue(label: "CPU", value: value, reservedValue: "100%", reservedLabel: "CPU"),
                        SensorStackValue(label: "GPU", value: value, reservedValue: "100%", reservedLabel: "GPU"),
                        SensorStackValue(
                            label: "TIME",
                            value: time,
                            reservedValue: BatteryTimeFormatter.reservedCompact,
                            reservedLabel: "TIME"
                        ),
                    ]).render(in: context).size.width
                )
            }
        }
        #expect(widths.count == 1, "stack produced widths \(widths.sorted())")
    }

    @Test("every two-row item puts its rows on the same lines")
    func twoRowItemsShareTheirRows() {
        // 22 is the real menu bar thickness on this Mac. Testing only at 24 hid a two-point drop,
        // because the offending expression happens to round to the same result there.
        for thickness in [22.0, 24.0, 26.0] {
            let ctx = RenderContext(
                thickness: thickness,
                appearance: .dark,
                palette: MenuBarPalette(light: .black, dark: .white),
                fontSize: RenderContext.referenceFontSize,
                isMonochrome: true,
                scale: RenderContext.referenceScale
            )
            let reference = Self.rowOrigins(
                StackedLabelRenderer(label: "CPU", value: "7:30", reservedValue: "99:99").render(in: ctx)
            )
            // Two live rows with no leading arrow.
            let bare = Self.rowOrigins(
                NetworkRateStackRenderer(
                    top: "78%", bottom: "7:30", reservedTop: "100%", reservedBottom: "99:99"
                ).render(in: ctx)
            )
            // The same renderer with arrows, which Network uses.
            let arrows = Self.rowOrigins(
                NetworkRateStackRenderer(
                    download: "1.2M", upload: "15K", reservedValue: "999MB/s"
                ).render(in: ctx)
            )
            #expect(reference.count == 2)
            #expect(bare.count == 2)
            #expect(arrows.count == 2)
            for row in 0..<min(2, min(reference.count, bare.count)) {
                #expect(
                    abs(reference[row] - bare[row]) <= 1,
                    "at \(thickness) pt, row \(row) sits at \(bare[row]) instead of \(reference[row])"
                )
            }
            for row in 0..<min(2, min(reference.count, arrows.count)) {
                #expect(abs(reference[row] - arrows[row]) <= 1)
            }
        }
    }

    /// Top edge of each contiguous band of ink, measured down from the image top.
    private static func rowOrigins(_ image: NSImage) -> [CGFloat] {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else {
            return []
        }
        let scale = CGFloat(bitmap.pixelsHigh) / image.size.height
        var origins: [CGFloat] = []
        var inBand = false
        for y in 0..<bitmap.pixelsHigh {
            var hasInk = false
            for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
                hasInk = true
                break
            }
            if hasInk, !inBand {
                origins.append(CGFloat(y) / scale)
            }
            inBand = hasInk
        }
        return origins
    }

    @Test("condition glyphs keep a stable field and center their visible artwork")
    func inlineIconsShareOneField() throws {
        var widths: Set<Double> = []
        var centers: [CGFloat] = []
        for name in ["sun.max", "cloud.sun", "cloud", "cloud.bolt.rain", "moon.stars", "snowflake"] {
            let image = IconTextRenderer(
                symbolName: name,
                text: "80°",
                reservedText: "-99°",
                reservedSymbolNames: ["sun.max", "cloud.sun", "cloud.bolt.rain"]
            ).render(in: context)
            widths.insert(image.size.width)
            // Inspect only the symbol's ink. Different aspect ratios must share a center, not
            // a left edge: requiring equal left margins incorrectly rejects centered narrow glyphs.
            let symbol = IconTextRenderer(symbolName: name, text: "").render(in: context)
            let tiff = try #require(symbol.tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: tiff))
            let columns = (0..<bitmap.pixelsWide).filter { x in
                (0..<bitmap.pixelsHigh).contains { y in
                    (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05
                }
            }
            let first = try #require(columns.first, "Missing glyph \(name)")
            let last = try #require(columns.last)
            let pixelScale = CGFloat(bitmap.pixelsWide) / symbol.size.width
            centers.append(CGFloat(first + last + 1) / (2 * pixelScale))
        }
        #expect(widths.count == 1, "condition glyphs produced widths \(widths.sorted())")
        let spread = (centers.max() ?? 0) - (centers.min() ?? 0)
        #expect(spread <= 1, "condition glyph centers vary by \(spread) pt: \(centers)")
    }

    /// Blank columns before the first inked column.
    private static func leadingInkMargin(_ image: NSImage) -> CGFloat {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else {
            return 0
        }
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
                return CGFloat(x) / (CGFloat(bitmap.pixelsWide) / image.size.width)
            }
        }
        return 0
    }

    @Test("an icon beside a value is spaced like every other multi-part item")
    func inlineIconSpacingMatchesTheRestOfTheBar() {
        // The gap is measured from the rendered ink, not from the layout constants, because the
        // constants differ: this renderer positions the icon by its ink and has no side bearing to
        // contribute, while a label-and-value pair does.
        let weather = Self.widestInteriorGap(
            IconTextRenderer(
                symbolName: "cloud.sun",
                text: "81°",
                reservedText: "-99°",
                reservedSymbolNames: ["cloud.sun", "sun.max", "cloud.bolt.rain", "questionmark.circle"]
            ).render(in: context)
        )
        let network = Self.widestInteriorGap(
            NetworkRateStackRenderer(download: "1.2M", upload: "15K", reservedValue: "999MB/s")
                .render(in: context)
        )
        let sensors = Self.widestInteriorGap(
            SensorStackRenderer(values: [
                SensorStackValue(label: "CPU", value: "12%", reservedValue: "100%", reservedLabel: "CPU")
            ]).render(in: context)
        )

        // Gaps are compared with a tolerance rather than for equality: the measurement is of drawn
        // ink, and how close a glyph's ink comes to the edge of its field varies with the symbol's
        // shape, the bar height, and the icon scale. The contract is that the icon sits in the same
        // spacing family as the rest of the bar, checked at 22 points, the real menu bar height on
        // this hardware.
        #expect(abs(weather - network) <= 2, "icon \(weather) vs network \(network) at 24 pt")
        #expect(abs(weather - sensors) <= 2, "icon \(weather) vs sensors \(sensors) at 24 pt")

        let liveBar = RenderContext(
            thickness: 22,
            appearance: .dark,
            palette: MenuBarPalette(light: .black, dark: .white),
            fontSize: RenderContext.referenceFontSize,
            isMonochrome: true,
            scale: RenderContext.referenceScale
        )
        let liveWeather = Self.widestInteriorGap(
            IconTextRenderer(
                symbolName: "cloud.sun",
                text: "81°",
                reservedText: "-99°",
                reservedSymbolNames: ["cloud.sun", "sun.max", "cloud.bolt.rain", "questionmark.circle"]
            ).render(in: liveBar)
        )
        let liveNetwork = Self.widestInteriorGap(
            NetworkRateStackRenderer(download: "1.2M", upload: "15K", reservedValue: "999MB/s")
                .render(in: liveBar)
        )
        #expect(
            abs(liveWeather - liveNetwork) <= 2,
            "at 22 pt the icon uses \(liveWeather) where the network item uses \(liveNetwork)"
        )
    }

    /// Widest run of blank columns between the first and last inked column.
    private static func widestInteriorGap(_ image: NSImage) -> CGFloat {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else {
            return 0
        }
        var inked: [Bool] = []
        for x in 0..<bitmap.pixelsWide {
            var hasInk = false
            for y in 0..<bitmap.pixelsHigh where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
                hasInk = true
                break
            }
            inked.append(hasInk)
        }
        guard let first = inked.firstIndex(of: true), let last = inked.lastIndex(of: true) else {
            return 0
        }
        var widest = 0
        var run = 0
        for x in first...last {
            run = inked[x] ? 0 : run + 1
            widest = max(widest, run)
        }
        return CGFloat(widest) / (CGFloat(bitmap.pixelsWide) / image.size.width)
    }

    @Test("the weather glyph stays legible at every automatic icon scale")
    func weatherGlyphIsGatedAtALegibleSize() {
        // The icon scale drops as items are added, which had shrunk the glyph until it read as
        // microscopic beside its temperature.
        var widths: Set<Double> = []
        for count in [3, 6, 8, 11, 14, 16] {
            let scaled = RenderContext(
                thickness: 24,
                appearance: .dark,
                palette: MenuBarPalette(light: .black, dark: .white),
                fontSize: RenderContext.referenceFontSize,
                isMonochrome: true,
                scale: AppSettings.menuBarScale(forItemCount: count)
            )
            let image = IconTextRenderer(
                symbolName: "cloud.sun",
                text: "81°",
                reservedText: "-99°",
                reservedSymbolNames: ["cloud.sun", "sun.max", "cloud.bolt.rain"]
            ).render(in: scaled)
            widths.insert(image.size.width)
            let glyphHeight = Self.topBandHeight(image)
            // Each glyph is fitted into one square field, so a wide symbol like cloud.sun meets the
            // field on its width and is correspondingly shorter. The contract is that it fills the
            // field in at least one direction and never spills past it, at every automatic scale.
            let field = MenuBarLayoutMetrics(context: scaled).inlineSymbolFieldSize
            #expect(
                glyphHeight <= field + 0.5,
                "glyph was \(glyphHeight) pt in a \(field) pt field at \(count) items"
            )
            #expect(
                glyphHeight >= field * 0.6,
                "glyph was \(glyphHeight) pt in a \(field) pt field at \(count) items"
            )
        }
        // The canvas is sized by the reserved text, so a larger glyph must not move the item.
        #expect(widths.count == 1, "weather widths varied: \(widths.sorted())")
    }

    /// Height of the tallest contiguous band of ink, top-down.
    private static func topBandHeight(_ image: NSImage) -> CGFloat {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else {
            return 0
        }
        var first = -1
        for y in 0..<bitmap.pixelsHigh {
            var hasInk = false
            for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
                hasInk = true
                break
            }
            if hasInk, first < 0 { first = y }
            if !hasInk, first >= 0 {
                return CGFloat(y - first) / (CGFloat(bitmap.pixelsHigh) / image.size.height)
            }
        }
        return 0
    }

    @Test("two bare readings stacked in one item share a center")
    func stackedReadingsShareACenter() {
        // Rows with arrows keep one leading column so the markers line up. Rows without them are two
        // readings of different lengths, and left-aligning leaves a visibly ragged column.
        for (charge, minutes) in [(78.0, 450), (5.0, 3), (100.0, 725), (9.0, 62)] {
            let image = BatteryMenuBarPresenter.content(
                sample: batterySample(charge: charge, charging: false, minutes: minutes),
                moduleSettings: ModuleSettings(mode: "percentageTime"),
                batterySettings: BatterySettings(),
                context: context
            ).image
            let centers = Self.rowCenters(image)
            #expect(centers.count == 2)
            #expect(abs(centers[0] - centers[1]) <= 1, "\(Int(charge))% rows differ by \(centers)")
        }

        // The Network item still pins its arrows to one leading column.
        let network = NetworkRateStackRenderer(
            download: "1.2M", upload: "15K", reservedValue: "999MB/s"
        ).render(in: context)
        let networkEdges = Self.rowLeadingEdges(network)
        #expect(networkEdges.count == 2)
        #expect(abs(networkEdges[0] - networkEdges[1]) <= 1, "network arrows misaligned: \(networkEdges)")
    }

    /// Horizontal center of the ink in the top and bottom halves of an image.
    private static func rowCenters(_ image: NSImage) -> [CGFloat] {
        bands(image) { first, last, scale in (CGFloat(first) + CGFloat(last)) / 2 / scale }
    }

    /// Leading ink edge in the top and bottom halves of an image.
    private static func rowLeadingEdges(_ image: NSImage) -> [CGFloat] {
        bands(image) { first, _, scale in CGFloat(first) / scale }
    }

    private static func bands(
        _ image: NSImage,
        _ measure: (Int, Int, CGFloat) -> CGFloat
    ) -> [CGFloat] {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else {
            return []
        }
        let middle = bitmap.pixelsHigh / 2
        return [(0, middle), (middle, bitmap.pixelsHigh)].map { band in
            var first = bitmap.pixelsWide
            var last = -1
            for x in 0..<bitmap.pixelsWide {
                for y in band.0..<band.1 where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
                    first = min(first, x)
                    last = max(last, x)
                    break
                }
            }
            guard last >= 0 else { return 0 }
            return measure(first, last, CGFloat(bitmap.pixelsWide) / image.size.width)
        }
    }

    private func batterySample(charge: Double, charging: Bool, minutes: Int? = nil) -> BatterySample {
        BatterySample(
            snapshot: BatterySnapshot(
                name: "Internal Battery",
                chargePercent: charge,
                state: charging ? .charging : .discharging,
                isExternalConnected: charging,
                isCharging: charging,
                isFullyCharged: false,
                healthPercent: nil,
                cycleCount: nil,
                temperatureCelsius: nil,
                voltageVolts: nil,
                amperageAmps: nil,
                wattageWatts: nil,
                condition: nil,
                adapter: nil,
                isLowPowerModeEnabled: false,
                timeToEmptyMinutes: charging ? nil : minutes,
                timeToFullMinutes: charging ? minutes : nil
            )
        )
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

        // One enabled stack that replaces the modules it draws from.
        settings.modules[.combined]?.isEnabled = true
        settings.stacks = StacksSettings(stacks: [
            StackSettings(
                id: 1,
                metrics: [.gpuUtilization, .weatherTemperature],
                hidesSourceItems: true
            )
        ])
        #expect(
            StatusItemRegistry.launchIdentities(settings: settings).map(\.autosaveName) == [
                "Barometer.CPU",
                "Barometer.Network",
                "Barometer.Sensors",
                "Barometer.Sensors.2",
                "Barometer.Combined",
            ]
        )

        // A second stack is its own movable item, numbered from its permanent identity.
        settings.stacks.stacks.append(StackSettings(id: 2, metrics: [.cpuTotal]))
        #expect(
            StatusItemRegistry.launchIdentities(settings: settings).map(\.autosaveName) == [
                "Barometer.CPU",
                "Barometer.Network",
                "Barometer.Sensors",
                "Barometer.Sensors.2",
                "Barometer.Combined",
                "Barometer.Combined.2",
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
