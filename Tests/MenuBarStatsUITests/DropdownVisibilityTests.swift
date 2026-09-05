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
