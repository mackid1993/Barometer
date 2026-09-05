import AppKit
import SwiftUI
@testable import MenuBarStatsCore
@testable import MenuBarStatsUI

@main
struct WeatherPanelMemoryBenchmark {
    @MainActor
    static func main() async throws {
        _ = NSApplication.shared
        let sample = try sample()
        let forecast = sample.forecast
        let suite = "PopoverMemoryBenchmark-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { exit(2) }
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONEncoder().encode(AppSettings()), forKey: SettingsStore.defaultsKey)
        let settingsStore = SettingsStore(defaults: defaults)
        let weatherStore = ModuleStore<WeatherSample>(historyCapacity: 1)
        weatherStore.receive(sample)
        let anchorWindow = NSWindow(contentRect: NSRect(x: 100, y: 700, width: 100, height: 30),
                                    styleMask: [.borderless], backing: .buffered, defer: false)
        anchorWindow.isReleasedWhenClosed = false
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 30))
        anchorWindow.contentView = anchor
        anchorWindow.orderFront(nil)
        let presenter = MenuDetailPresenter(pointerLocation: { NSPoint(x: 150, y: 715) })
        let rootController = DropdownController(
            moduleName: "Weather",
            statusItem: nil,
            rootView: AnyView(
                WeatherDropdownView(store: weatherStore, settingsStore: settingsStore, refreshAction: {})
            ),
            contentHeight: WeatherDropdownView.contentSize.height,
            contentWidth: WeatherDropdownView.contentSize.width,
            usesAttachedPanel: true,
            tickAction: { weatherStore.tick() },
            settingsAction: {},
            quitAction: {}
        )
        report(-1)
        for cycle in 0..<5 {
            for day in forecast.daily.prefix(2) {
                rootController.presentAttachedPanel(anchoredTo: anchor)
                let content = AnyView(WeatherDayDetailView(
                    day: day, sample: sample, accent: .signature(for: .weather)))
                presenter.present(content, anchoredTo: anchor)
                try await Task.sleep(for: .milliseconds(150))
                if let host = presenter.panel?.contentView {
                    host.layoutSubtreeIfNeeded()
                    if let scroll = scrollView(host), let document = scroll.documentView {
                        for fraction in stride(from: 0.0, through: 1.0, by: 0.1) {
                            let y = max(0, document.frame.height - scroll.contentView.bounds.height) * fraction
                            scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
                            scroll.reflectScrolledClipView(scroll.contentView)
                            try await Task.sleep(for: .milliseconds(60))
                        }
                    }
                }
                presenter.close()
                rootController.dismiss()
                try await Task.sleep(for: .milliseconds(100))
            }
            report(cycle)
        }
        anchorWindow.close()
    }

    static func sample() throws -> WeatherSample {
        if let cachePath = ProcessInfo.processInfo.environment["BAROMETER_WEATHER_CACHE"] {
            let entry = try JSONDecoder().decode(
                WeatherCacheEntry.self,
                from: Data(contentsOf: URL(fileURLWithPath: cachePath))
            )
            return WeatherSample(
                timestamp: entry.forecast.fetchedAt,
                forecast: entry.forecast,
                airQuality: entry.airQuality,
                isStale: false,
                refreshError: nil
            )
        }
        let location = Location(id: "boston", name: "Boston", admin: nil, country: "US",
                                latitude: 42.36, longitude: -71.05, timeZone: "America/New_York")
        let data = try Data(contentsOf: URL(fileURLWithPath:
            "Tests/MenuBarStatsCoreTests/Fixtures/forecast-rich-imperial.json"))
        let forecast = try OpenMeteoClient.decodeForecast(data, for: location, units: .imperial)
        return WeatherSample(timestamp: forecast.fetchedAt, forecast: forecast, airQuality: nil,
                             isStale: false, refreshError: nil)
    }

    @MainActor
    static func scrollView(_ view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.compactMap { scrollView($0) }.first
    }

    static func report(_ cycle: Int) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { exit(2) }
        print("cycle=\(cycle) current=\(info.phys_footprint) peak=\(info.ledger_phys_footprint_peak)")
    }
}
