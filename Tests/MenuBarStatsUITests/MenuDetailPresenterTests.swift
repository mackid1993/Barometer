import AppKit
import SwiftUI
import Testing
@testable import MenuBarStatsCore
@testable import MenuBarStatsUI

@Suite("Menu detail lifecycle", .serialized)
@MainActor
struct MenuDetailPresenterTests {
    @Test("Detail content scrolls beyond its visible window")
    func scrolling() async throws {
        let presenter = MenuDetailPresenter()
        let location = Location(id: "boston", name: "Boston", admin: nil, country: "US",
                                latitude: 42.36, longitude: -71.05, timeZone: "America/New_York")
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MenuBarStatsCoreTests/Fixtures/forecast-rich-imperial.json")
        let forecast = try OpenMeteoClient.decodeForecast(Data(contentsOf: fixture), for: location, units: .imperial)
        let sample = WeatherSample(timestamp: forecast.fetchedAt, forecast: forecast, airQuality: nil,
                                   isStale: false, refreshError: nil)
        let day = try #require(forecast.daily.first)
        let content = WeatherDayDetailView(day: day, sample: sample, accent: .signature(for: .weather))
        presenter.present(AnyView(content), at: NSPoint(x: 100, y: 700))
        defer { presenter.close() }
        let panel = try #require(presenter.panel)
        for _ in 0..<5 {
            await Task.yield()
            panel.contentView?.layoutSubtreeIfNeeded()
        }
        func findScroll(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.compactMap { findScroll($0) }.first
        }
        let host = try #require(panel.contentView)
        let scroll = try #require(findScroll(host))
        let document = try #require(scroll.documentView)
        #expect(document.frame.height > scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 500))
        scroll.reflectScrolledClipView(scroll.contentView)
        #expect(scroll.contentView.bounds.origin.y > 0)
    }

    @Test("Closing a detail removes its window and releases hosted content")
    func closeReleasesContent() throws {
        let presenter = MenuDetailPresenter()
        presenter.present(AnyView(Text("Detail")), at: NSPoint(x: 100, y: 500))
        let panel = try #require(presenter.panel)
        #expect(panel.isVisible)
        #expect(panel.canBecomeKey)
        presenter.close()
        #expect(!panel.isVisible)
        #expect(panel.contentView == nil)
        #expect(presenter.panel == nil)
    }

    @Test("Replacement and loss of focus cannot leave an old detail window visible")
    func replacementAndFocusLoss() throws {
        let presenter = MenuDetailPresenter()
        presenter.present(AnyView(Text("First")), at: NSPoint(x: 100, y: 500))
        let old = try #require(presenter.panel)
        presenter.present(AnyView(Text("Second")), at: NSPoint(x: 100, y: 500))
        let current = try #require(presenter.panel)
        #expect(old !== current)
        #expect(!old.isVisible)
        #expect(old.contentView == nil)
        presenter.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: current))
        #expect(!current.isVisible)
        #expect(presenter.panel == nil)
    }
}
