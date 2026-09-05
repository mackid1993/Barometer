import AppKit
import SwiftUI
import Testing
@testable import MenuBarStatsUI
@testable import MenuBarStatsCore

@Suite("Popover screen placement", .serialized)
@MainActor
struct PopoverPlacementTests {
    @Test("Every weather and Combined popover fits at all four display corners in light and dark mode")
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
                            let popover = NSPopover()
                            popover.animates = false
                            popover.appearance = NSAppearance(named: appearance)
                            let height = min(name.hasPrefix("day") ? 640.0 : 720.0, visible.height - 100)
                            PopoverPlacement.configure(popover, content: view.frame(width: 380, height: height),
                                                       size: NSSize(width: 380, height: height))
                            popover.show(relativeTo: anchor.bounds, of: anchor,
                                         preferredEdge: name.hasPrefix("day") ? .maxX : .minY)
                            PopoverPlacement.constrain(popover, to: screen)
                            let window = try #require(popover.contentViewController?.view.window)
                            window.contentView?.layoutSubtreeIfNeeded()
                            #expect(visible.contains(window.frame), "\(name): \(window.frame) outside \(visible)")
                            if let directory = ProcessInfo.processInfo.environment["POPOVER_SNAPSHOT_DIRECTORY"] {
                                // Explicit opt-in only; screen-capture permission must already be granted.
                                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
                                let capture = Process()
                                capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                                let corner = "\(x == visible.minX ? "left" : "right")-\(y == visible.minY ? "bottom" : "top")"
                                let path = URL(fileURLWithPath: directory)
                                    .appendingPathComponent("\(name)-\(appearance.rawValue)-\(corner).png").path
                                capture.arguments = ["-x", "-l", String(window.windowNumber), path]
                                try capture.run()
                                capture.waitUntilExit()
                                #expect(capture.terminationStatus == 0, "Window capture failed for \(name)")
                                #expect(visible.contains(window.frame), "\(name) moved off-screen after display")
                            }
                            popover.close()
                            popover.contentViewController = nil
                        }
                    }
                }
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
                let popover = NSPopover()
                popover.animates = false
                let height = min(640, visible.height - 100)
                let content = ScrollView { VStack { ForEach(0..<100) { Text("Hour \($0)").frame(height: 40) } } }
                    .frame(width: 380, height: height)
                PopoverPlacement.configure(popover, content: content, size: NSSize(width: 380, height: height))
                popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
                PopoverPlacement.constrain(popover, to: screen)
                let window = try #require(popover.contentViewController?.view.window)
                window.contentView?.layoutSubtreeIfNeeded()
                #expect(visible.contains(window.frame))
                #expect(popover.contentSize.height <= height)
                popover.close()
                popover.contentViewController = nil
            }
        }
    }
}
