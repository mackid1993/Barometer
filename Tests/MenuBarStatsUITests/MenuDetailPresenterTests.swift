import AppKit
import SwiftUI
import Testing
@testable import MenuBarStatsCore
@testable import MenuBarStatsUI

@Suite("Menu detail lifecycle", .serialized)
@MainActor
struct MenuDetailPresenterTests {
    private func makeAnchor() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 700, width: 100, height: 30),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 30))
        window.orderFront(nil)
        return window
    }

    private func weatherContent() throws -> WeatherDayDetailView {
        let location = Location(id: "boston", name: "Boston", admin: nil, country: "US",
                                latitude: 42.36, longitude: -71.05, timeZone: "America/New_York")
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MenuBarStatsCoreTests/Fixtures/forecast-rich-imperial.json")
        let forecast = try OpenMeteoClient.decodeForecast(Data(contentsOf: fixture), for: location, units: .imperial)
        let sample = WeatherSample(timestamp: forecast.fetchedAt, forecast: forecast, airQuality: nil,
                                   isStale: false, refreshError: nil)
        let day = try #require(forecast.daily.first)
        return WeatherDayDetailView(day: day, sample: sample, accent: .signature(for: .weather))
    }

    @Test("Hover enters a day without requiring a mouse click")
    func hoverOpensDetail() throws {
        let view = WeatherHoverAnchor.HoverView()
        var entered = false
        view.show = { anchor in entered = anchor === view }
        let event = try #require(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 1, trackingNumber: 1, userData: nil))
        view.mouseEntered(with: event)
        #expect(entered)
        view.show = nil
    }

    @Test("Leaving the row and detail dismisses it, but moving into the detail keeps it open")
    func hoverExitDismissal() throws {
        let anchorWindow = makeAnchor()
        defer { anchorWindow.close() }
        let anchor = try #require(anchorWindow.contentView)
        let presenter = MenuDetailPresenter(pointerLocation: { NSPoint(x: 150, y: 715) })
        defer { presenter.close() }
        presenter.present(AnyView(Text("Forecast")), anchoredTo: anchor)
        let detail = try #require(presenter.popover)
        let detailWindow = try #require(detail.contentViewController?.view.window)
        let row = anchorWindow.convertToScreen(anchor.bounds)
        let start = ProcessInfo.processInfo.systemUptime
        presenter.updateHover(at: NSPoint(x: row.midX, y: row.midY), time: start)
        let outside = NSPoint(x: -100_000, y: -100_000)
        presenter.updateHover(at: outside, time: start + 0.1)
        #expect(detail.isShown)
        presenter.updateHover(at: NSPoint(x: detailWindow.frame.midX, y: detailWindow.frame.midY), time: start + 0.15)
        presenter.updateHover(at: NSPoint(x: detailWindow.frame.midX, y: detailWindow.frame.midY), time: start + 5)
        #expect(detail.isShown)
        presenter.updateHover(at: outside, time: start + 5.25)
        #expect(!detail.isShown)
        #expect(presenter.popover == nil)
        #expect(detail.contentViewController == nil)
    }

    @Test("Presentation waits until the menu tracking run loop ends")
    func menuHandoff() throws {
        let anchorWindow = makeAnchor()
        defer { anchorWindow.close() }
        let anchor = try #require(anchorWindow.contentView)
        let presenter = MenuDetailPresenter(pointerLocation: { NSPoint(x: 150, y: 715) })
        defer { presenter.close() }
        presenter.show(AnyView(Text("Day forecast")), from: NSMenu(), anchoredTo: anchor)
        RunLoop.main.run(mode: .eventTracking, before: Date(timeIntervalSinceNow: 0.02))
        #expect(presenter.popover == nil)
        let deadline = Date(timeIntervalSinceNow: 1)
        while presenter.popover == nil && Date() < deadline {
            RunLoop.main.run(mode: .default, before: deadline)
        }
        let panel = try #require(presenter.popover)
        #expect(panel.isShown)
        panel.contentViewController?.view.window?.resignKey()
        #expect(panel.isShown)
        panel.performClose(nil)
        #expect(presenter.popover == nil)
    }

    @Test("Repeated presentation releases popovers, hosts, and canceled presentation timers")
    func repeatedPresentationReleasesMemory() async throws {
        let content = try weatherContent()
        weak var lastPanel: NSPopover?
        weak var lastHost: NSView?
        weak var releasedPresenter: MenuDetailPresenter?
        let anchorWindow = makeAnchor()
        defer { anchorWindow.close() }
        let anchor = try #require(anchorWindow.contentView)
        autoreleasepool {
            let presenter = MenuDetailPresenter(pointerLocation: { NSPoint(x: 150, y: 715) })
            releasedPresenter = presenter
            for _ in 0..<100 {
                autoreleasepool {
                    presenter.present(AnyView(content), anchoredTo: anchor)
                    lastPanel = presenter.popover
                    lastHost = presenter.popover?.contentViewController?.view
                    presenter.close()
                }
            }
            presenter.show(AnyView(Text("Canceled day")), from: NSMenu(), anchoredTo: anchor)
            presenter.close()
        }
        for _ in 0..<10 { await Task.yield() }
        #expect(lastPanel == nil)
        #expect(lastHost == nil)
        #expect(releasedPresenter == nil)
    }

    @Test("Detail content scrolls beyond its visible window")
    func scrolling() async throws {
        let anchorWindow = makeAnchor()
        defer { anchorWindow.close() }
        let anchor = try #require(anchorWindow.contentView)
        let presenter = MenuDetailPresenter(pointerLocation: { NSPoint(x: 150, y: 715) })
        let parent = NSPopover()
        parent.behavior = .transient
        parent.animates = false
        let parentController = NSViewController()
        parentController.view = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 500))
        parent.contentViewController = parentController
        parent.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        defer { parent.close() }
        let content = try weatherContent()
        presenter.present(AnyView(content), anchoredTo: parentController.view, edge: .maxX)
        defer { presenter.close() }
        let panel = try #require(presenter.popover)
        for _ in 0..<5 {
            await Task.yield()
            panel.contentViewController?.view.layoutSubtreeIfNeeded()
        }
        func findScroll(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.compactMap { findScroll($0) }.first
        }
        #expect(parent.isShown)
        #expect(panel.isShown)
        #expect(!panel.isDetached)
        let host = try #require(panel.contentViewController?.view)
        let scroll = try #require(findScroll(host))
        let document = try #require(scroll.documentView)
        #expect(document.frame.height > scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 500))
        scroll.reflectScrolledClipView(scroll.contentView)
        #expect(scroll.contentView.bounds.origin.y > 0)
    }

    @Test("Closing a detail removes its popover and releases hosted content")
    func closeReleasesContent() throws {
        let anchorWindow = makeAnchor()
        defer { anchorWindow.close() }
        let anchor = try #require(anchorWindow.contentView)
        let presenter = MenuDetailPresenter(pointerLocation: { NSPoint(x: 150, y: 715) })
        presenter.present(AnyView(Text("Detail")), anchoredTo: anchor)
        let panel = try #require(presenter.popover)
        #expect(panel.isShown)
        #expect(!panel.isDetached)
        #expect(!presenter.popoverShouldDetach(panel))
        presenter.close()
        #expect(!panel.isShown)
        #expect(panel.contentViewController == nil)
        #expect(presenter.popover == nil)
    }

    @Test("Replacement removes the old window and focus changes do not dismiss the new one")
    func replacementAndFocusLoss() throws {
        let anchorWindow = makeAnchor()
        defer { anchorWindow.close() }
        let anchor = try #require(anchorWindow.contentView)
        let presenter = MenuDetailPresenter(pointerLocation: { NSPoint(x: 150, y: 715) })
        presenter.present(AnyView(Text("First")), anchoredTo: anchor)
        let old = try #require(presenter.popover)
        presenter.present(AnyView(Text("Second")), anchoredTo: anchor)
        let current = try #require(presenter.popover)
        #expect(old !== current)
        #expect(!old.isShown)
        #expect(old.contentViewController == nil)
        current.contentViewController?.view.window?.resignKey()
        #expect(current.isShown)
        #expect(presenter.popover === current)
        presenter.close()
        #expect(!current.isShown)
    }
}
