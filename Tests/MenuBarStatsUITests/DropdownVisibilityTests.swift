import AppKit
import SwiftUI
import Testing
@testable import MenuBarStatsUI

@MainActor
@Test("Every module reports open and close without treating content updates as opens",
      arguments: ["CPU", "GPU", "Memory", "Disks", "Network", "Sensors", "Battery", "Weather", "Time", "Combined"])
func dropdownVisibility(module: String) {
    var visibility: [Bool] = []
    let controller = DropdownController(
        moduleName: module, statusItem: nil, rootView: AnyView(Text("CPU")), contentHeight: 100,
        visibilityAction: { visibility.append($0) }, tickAction: {}, settingsAction: {}, quitAction: {}
    )
    let menu = NSMenu()
    controller.menuNeedsUpdate(menu)
    #expect(visibility.isEmpty)
    controller.menuWillOpen(menu)
    controller.menuNeedsUpdate(menu)
    #expect(visibility == [true])
    controller.menuDidClose(menu)
    #expect(visibility == [true, false])
}

@MainActor
@Test("Opening another Barometer dropdown closes the previous hosted UI")
func dropdownExclusivity() {
    var firstVisibility: [Bool] = []
    var secondVisibility: [Bool] = []
    let first = DropdownController(
        moduleName: "CPU", statusItem: nil, rootView: AnyView(Text("CPU")), contentHeight: 100,
        visibilityAction: { firstVisibility.append($0) }, tickAction: {}, settingsAction: {}, quitAction: {}
    )
    let second = DropdownController(
        moduleName: "Memory", statusItem: nil, rootView: AnyView(Text("Memory")), contentHeight: 100,
        visibilityAction: { secondVisibility.append($0) }, tickAction: {}, settingsAction: {}, quitAction: {}
    )
    let firstMenu = NSMenu()
    let secondMenu = NSMenu()
    first.menuWillOpen(firstMenu)
    second.menuWillOpen(secondMenu)
    #expect(firstVisibility == [true, false])
    #expect(secondVisibility == [true])
    second.menuDidClose(secondMenu)
    #expect(secondVisibility == [true, false])
}

@MainActor
@Test("Attached dropdowns observe their stores instead of polling while open")
func attachedDropdownDoesNotPoll() {
    var ticks = 0
    let window = NSWindow(
        contentRect: NSRect(x: 100, y: 100, width: 40, height: 24),
        styleMask: .borderless,
        backing: .buffered,
        defer: false
    )
    let anchor = NSView(frame: window.contentView?.bounds ?? .zero)
    window.contentView = anchor
    let controller = DropdownController(
        moduleName: "Weather", statusItem: nil, rootView: AnyView(Text("Weather")), contentHeight: 100,
        usesAttachedPanel: true, tickAction: { ticks += 1 }, settingsAction: {}, quitAction: {}
    )

    controller.presentAttachedPanel(anchoredTo: anchor)

    #expect(!controller.hasActiveTrackingTimer)
    #expect(ticks == 0)
    controller.dismiss()
}
