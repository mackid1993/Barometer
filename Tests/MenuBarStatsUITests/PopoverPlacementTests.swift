import AppKit
import SwiftUI
import Testing
@testable import MenuBarStatsUI
@testable import MenuBarStatsCore

@Suite("Popover screen placement", .serialized)
@MainActor
struct PopoverPlacementTests {
    @Test("Every weather and Combined panel fits at all four display corners in light and dark mode")
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
        var views: [(String, AnyView)] = [
            ("weather", AnyView(WeatherDropdownView(store: store, settingsStore: settingsStore, refreshAction: {}))),
            ("combined", AnyView(CombinedDropdownView(stackID: 1,
                cpuStore: .init(historyCapacity: 1), memoryStore: .init(historyCapacity: 1),
                gpuStore: .init(historyCapacity: 1), networkStore: .init(historyCapacity: 1),
                diskStore: .init(historyCapacity: 1), sensorStore: .init(historyCapacity: 1),
                batteryStore: .init(historyCapacity: 1), weatherStore: store, timeStore: .init(historyCapacity: 1),
                settingsStore: settingsStore, locationAccess: { .unavailable }, locationAction: {},
                weatherRefreshAction: {}, resetEnergyAction: {}, requestCalendarAccess: {})))
        ]
        for (index, day) in forecast.daily.enumerated() {
            views.append(("day-\(index)", AnyView(WeatherDayDetailView(
                day: day, sample: sample, accent: .signature(for: .weather)))))
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
                for (name, view) in views {
                    for x in [visible.minX, visible.maxX - 24] {
                        for y in [visible.minY, visible.maxY - 24] {
                            anchorWindow.setFrameOrigin(NSPoint(x: x, y: y))
                            anchorWindow.orderFront(nil)
                            let height = min(name.hasPrefix("day") ? 640.0 : 720.0, visible.height - 100)
                            let panel = AttachedPanel(content: AnyView(view.frame(width: 380, height: height)),
                                                      size: NSSize(width: 380, height: height))
                            panel.appearance = NSAppearance(named: appearance)
                            let anchorRect = anchorWindow.convertToScreen(anchor.bounds)
                            panel.show(relativeTo: anchorRect,
                                       preferredEdge: name.hasPrefix("day") ? .maxX : .minY, on: screen)
                            panel.contentView?.layoutSubtreeIfNeeded()
                            #expect(visible.contains(panel.frame), "\(name): \(panel.frame) outside \(visible)")
                            if let directory = ProcessInfo.processInfo.environment["POPOVER_SNAPSHOT_DIRECTORY"] {
                                // Explicit opt-in only; screen-capture permission must already be granted.
                                let corner = "\(x == visible.minX ? "left" : "right")-\(y == visible.minY ? "bottom" : "top")"
                                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
                                let baseName = "\(name)-\(appearance.rawValue)-\(corner)"
                                try capture(panel, named: baseName, in: directory)
                                if let scroll = Self.verticalScrollView(in: panel.contentView),
                                   let document = scroll.documentView {
                                    let maximumY = max(0, document.frame.height - scroll.contentView.bounds.height)
                                    if maximumY > 1 {
                                        Self.scrollToBottom(scroll)
                                        try capture(panel, named: "\(baseName)-bottom", in: directory)
                                        let finalMaximumY = max(
                                            0, (scroll.documentView?.frame.height ?? 0) - scroll.contentView.bounds.height)
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

    private func capture(_ panel: NSPanel, named name: String, in directory: String) throws {
        let path = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png").path
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-l", String(panel.windowNumber), path]
        try capture.run()
        capture.waitUntilExit()
        #expect(capture.terminationStatus == 0, "Window capture failed for \(name)")
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
