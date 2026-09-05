import AppKit
import SwiftUI
import Testing
@testable import MenuBarStatsUI
@testable import MenuBarStatsCore

@Suite("Popover screen placement", .serialized)
@MainActor
struct PopoverPlacementTests {
    @Test("Every custom panel and changed dropdown view fits at all display corners")
    func everyPopoverOnScreen() throws {
        let suite = "PopoverScreenTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = AppSettings()
        settings.stacks = StacksSettings(stacks: [StackSettings(id: 1, metrics: [.weatherTemperature])])
        defaults.set(try JSONEncoder().encode(settings), forKey: SettingsStore.defaultsKey)
        let settingsStore = SettingsStore(defaults: defaults)
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MenuBarStatsCoreTests/Fixtures/forecast-rich-imperial.json")
        let location = Location(id: "boston", name: "Boston", admin: nil, country: "US",
                                latitude: 42.36, longitude: -71.05, timeZone: "America/New_York")
        let forecast = try OpenMeteoClient.decodeForecast(Data(contentsOf: fixture), for: location, units: .imperial)
        let sample = WeatherSample(timestamp: forecast.fetchedAt, forecast: forecast, airQuality: nil,
                                   isStale: false, refreshError: nil)
        let store = ModuleStore<WeatherSample>(historyCapacity: 1)
        store.receive(sample)
        let networkStore = ModuleStore<NetworkSample>(historyCapacity: 60)
        let cpuStore = ModuleStore<CPUSample>(historyCapacity: 60)
        for index in 0..<60 {
            let timestamp = Date().addingTimeInterval(Double(index - 59))
            networkStore.receive(NetworkSample(
                timestamp: timestamp,
                interfaces: [
                    Self.networkInterface(
                        "en0", download: Double(index + 1) * 20_000, upload: Double(60 - index) * 1_400),
                    Self.networkInterface("utun3", isVPN: true, download: 20_000, upload: 10_000),
                ],
                primaryInterface: "en0",
                router: "192.0.2.1",
                dnsServers: ["192.0.2.53"],
                wifi: nil,
                publicIP: nil
            ), at: timestamp)
            cpuStore.receive(Self.cpuSample(timestamp: timestamp, percent: Double(index + 20)), at: timestamp)
        }
        var views: [(String, () -> AnyView, CGFloat)] = HistoryRange.allCases.map { range in
            (
                "cpu-\(range.rawValue)",
                { AnyView(CPUDropdownView(
                    store: cpuStore,
                    settingsStore: settingsStore,
                    initialRange: range
                )) },
                500
            )
        }
        views.append(contentsOf: [
            ("weather", { AnyView(WeatherDropdownView(
                store: store, settingsStore: settingsStore, refreshAction: {})) }, 720),
            ("network", { AnyView(NetworkDropdownView(
                store: networkStore,
                settingsStore: settingsStore,
                locationAccess: { .authorized },
                locationAction: {}
            )) }, 560),
            ("combined", { AnyView(CombinedDropdownView(stackID: 1,
                cpuStore: cpuStore, memoryStore: .init(historyCapacity: 1),
                gpuStore: .init(historyCapacity: 1), networkStore: .init(historyCapacity: 1),
                diskStore: .init(historyCapacity: 1), sensorStore: .init(historyCapacity: 1),
                batteryStore: .init(historyCapacity: 1), weatherStore: store, timeStore: .init(historyCapacity: 1),
                settingsStore: settingsStore, locationAccess: { .unavailable }, locationAction: {},
                weatherRefreshAction: {}, resetEnergyAction: {}, requestCalendarAccess: {})) }, 720)
        ])
        for (index, day) in forecast.daily.enumerated() {
            views.append(("day-\(index)", { AnyView(WeatherDayDetailView(
                day: day, sample: sample, accent: .signature(for: .weather))) }, 640))
        }
        for screen in NSScreen.screens {
            let visible = screen.visibleFrame
            let anchorWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 24, height: 24),
                                        styleMask: [.borderless], backing: .buffered, defer: false)
            anchorWindow.isReleasedWhenClosed = false
            defer { anchorWindow.close() }
            let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
            anchorWindow.contentView = anchor
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                for (name, makeView, requestedHeight) in views {
                    for x in [visible.minX, visible.maxX - 24] {
                        for y in [visible.minY, visible.maxY - 24] {
                            anchorWindow.setFrameOrigin(NSPoint(x: x, y: y))
                            anchorWindow.orderFront(nil)
                            let height = min(requestedHeight, visible.height - 100)
                            let panel = AttachedPanel(content: AnyView(makeView().frame(width: 380, height: height)),
                                                      size: NSSize(width: 380, height: height))
                            panel.appearance = NSAppearance(named: appearance)
                            let anchorRect = anchorWindow.convertToScreen(anchor.bounds)
                            panel.show(relativeTo: anchorRect,
                                       preferredEdge: name.hasPrefix("day") ? .maxX : .minY, on: screen)
                            panel.contentView?.layoutSubtreeIfNeeded()
                            #expect(visible.contains(panel.frame), "\(name): \(panel.frame) outside \(visible)")
                            if let directory = ProcessInfo.processInfo.environment["POPOVER_SNAPSHOT_DIRECTORY"] {
                                // Explicit opt-in only; screen-capture permission must already be granted.
                                let horizontal = x == visible.minX ? "left" : "right"
                                let vertical = y == visible.minY ? "bottom" : "top"
                                let corner = "\(horizontal)-\(vertical)"
                                RunLoop.main.run(
                                    until: Date(timeIntervalSinceNow: name.hasPrefix("cpu") ? 1 : 0.25)
                                )
                                panel.displayIfNeeded()
                                let baseName = "\(name)-\(appearance.rawValue)-\(corner)"
                                try capture(panel, named: baseName, in: directory)
                                if let scroll = Self.verticalScrollView(in: panel.contentView),
                                   let document = scroll.documentView {
                                    let maximumY = max(0, document.frame.height - scroll.contentView.bounds.height)
                                    if maximumY > 1 {
                                        if name.hasPrefix("day") {
                                            Self.scroll(scroll, to: maximumY * 0.55)
                                            try capture(panel, named: "\(baseName)-hourly", in: directory)
                                        }
                                        Self.scrollToBottom(scroll)
                                        try capture(panel, named: "\(baseName)-bottom", in: directory)
                                        let finalMaximumY = max(
                                            0,
                                            (scroll.documentView?.frame.height ?? 0) - scroll.contentView.bounds.height
                                        )
                                        #expect(abs(scroll.contentView.bounds.origin.y - finalMaximumY) <= 1,
                                                "Did not reach the bottom of \(name)")
                                    }
                                }
                                #expect(visible.contains(panel.frame), "\(name) moved off-screen after display")
                            }
                            panel.releaseAndClose()
                        }
                    }
                }
            }
        }
    }

    private static func networkInterface(
        _ name: String,
        isVPN: Bool = false,
        download: Double? = nil,
        upload: Double? = nil
    ) -> NetworkInterfaceSample {
        NetworkInterfaceSample(
            name: name,
            isUp: true,
            isLoopback: false,
            isVPN: isVPN,
            ipv4Addresses: name == "en0" ? ["192.0.2.10"] : [],
            ipv6Addresses: [],
            downloadBytesPerSecond: download ?? (name == "en0" ? 1_200_000 : 20_000),
            uploadBytesPerSecond: upload ?? (name == "en0" ? 82_000 : 10_000),
            receivedBytes: 10_000_000,
            sentBytes: 2_000_000,
            inputErrors: 0,
            outputErrors: 0
        )
    }

    private static func cpuSample(timestamp: Date, percent: Double) -> CPUSample {
        CPUSample(
            timestamp: timestamp,
            totalPercent: percent,
            userPercent: percent * 0.7,
            systemPercent: percent * 0.3,
            idlePercent: 100 - percent,
            nicePercent: 0,
            perCore: [
                CPUCoreSample(index: 0, kind: .performance, usagePercent: percent),
                CPUCoreSample(index: 1, kind: .efficiency, usagePercent: percent * 0.5),
            ],
            loadAverages: [1.2, 1.0, 0.8],
            uptime: 86_400,
            processCount: 420,
            threadCount: 2_400,
            topProcesses: []
        )
    }

    private func capture(_ panel: NSPanel, named name: String, in directory: String) throws {
        let path = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png").path
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-l", String(panel.windowNumber), path]
        try capture.run()
        capture.waitUntilExit()
        #expect(capture.terminationStatus == 0, "Window capture failed for \(name)")
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let image = try #require(NSBitmapImageRep(data: data), "Unreadable window capture for \(name)")
        let byteCount = image.bytesPerRow * image.pixelsHigh
        let bitmapData = try #require(image.bitmapData, "Window capture for \(name) has no bitmap data")
        let containsVisiblePixel = UnsafeBufferPointer(start: bitmapData, count: byteCount).contains { $0 != 0 }
        #expect(containsVisiblePixel, "Window capture for \(name) was fully transparent")
    }

    private static func verticalScrollView(in view: NSView?) -> NSScrollView? {
        guard let view else { return nil }
        if let scroll = view as? NSScrollView,
           let document = scroll.documentView,
           document.frame.height > scroll.contentView.bounds.height + 1 {
            return scroll
        }
        let candidates = view.subviews.compactMap { verticalScrollView(in: $0) }
        return candidates.max { lhs, rhs in
            (lhs.documentView?.frame.height ?? 0) < (rhs.documentView?.frame.height ?? 0)
        }
    }

    private static func scrollToBottom(_ scroll: NSScrollView) {
        var stablePasses = 0
        var previousMaximumY: CGFloat = -1
        for _ in 0..<20 {
            guard let document = scroll.documentView else { return }
            let maximumY = max(0, document.frame.height - scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: maximumY))
            scroll.reflectScrolledClipView(scroll.contentView)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
            if abs(maximumY - previousMaximumY) <= 1 {
                stablePasses += 1
                if stablePasses == 3 { return }
            } else {
                stablePasses = 0
                previousMaximumY = maximumY
            }
        }
    }

    private static func scroll(_ scroll: NSScrollView, to y: CGFloat) {
        scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
    }

    @Test("Oversized and off-screen frames fit displays with positive and negative origins")
    func screenBounds() {
        for visible in [NSRect(x: 0, y: 30, width: 1280, height: 690),
                        NSRect(x: -1920, y: -1080, width: 1920, height: 1050)] {
            for origin in [NSPoint(x: visible.minX - 500, y: visible.maxY + 500),
                           NSPoint(x: visible.maxX + 500, y: visible.minY - 500)] {
                let frame = PopoverPlacement.containedFrame(
                    NSRect(origin: origin, size: NSSize(width: 380, height: 1500)), in: visible)
                #expect(visible.contains(frame))
            }
        }
    }

    @Test("A tall scroll document stays inside the display at each screen corner")
    func tallContentAtScreenEdges() throws {
        let screen = try #require(NSScreen.main)
        let visible = screen.visibleFrame
        let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 24, height: 24),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        defer { host.close() }
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        host.contentView = anchor
        for x in [visible.minX, visible.maxX - 24] {
            for y in [visible.minY, visible.maxY - 24] {
                host.setFrameOrigin(NSPoint(x: x, y: y))
                host.orderFront(nil)
                let height = min(640, visible.height - 100)
                let content = ScrollView { VStack { ForEach(0..<100) { Text("Hour \($0)").frame(height: 40) } } }
                    .frame(width: 380, height: height)
                let panel = AttachedPanel(content: AnyView(content), size: NSSize(width: 380, height: height))
                panel.show(relativeTo: host.convertToScreen(anchor.bounds), preferredEdge: .minY, on: screen)
                panel.contentView?.layoutSubtreeIfNeeded()
                #expect(visible.contains(panel.frame))
                #expect(panel.frame.height <= height)
                panel.releaseAndClose()
            }
        }
    }
}
