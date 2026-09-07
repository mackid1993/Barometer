import AppKit
import SwiftUI
import Testing
@testable import MenuBarStatsUI

private func mouseEvent(_ type: NSEvent.EventType, modifiers: NSEvent.ModifierFlags = []) -> NSEvent? {
    NSEvent.mouseEvent(
        with: type, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
        eventNumber: 0, clickCount: 1, pressure: 1
    )
}

@MainActor
@Test("A plain left click is primary; right, middle, and Control clicks are secondary")
func primaryClickClassification() throws {
    #expect(DropdownController.isPrimaryClick(try #require(mouseEvent(.leftMouseUp))))
    #expect(DropdownController.isPrimaryClick(try #require(mouseEvent(.leftMouseUp, modifiers: [.option]))))
    #expect(DropdownController.isPrimaryClick(nil))
    #expect(!DropdownController.isPrimaryClick(try #require(mouseEvent(.leftMouseUp, modifiers: [.control]))))
    #expect(!DropdownController.isPrimaryClick(try #require(mouseEvent(.rightMouseUp))))
    #expect(!DropdownController.isPrimaryClick(try #require(mouseEvent(.otherMouseUp))))
}

@MainActor
@Test("The primary click handler sees left clicks only and can decline them")
func primaryClickHandlerReceivesLeftClicksOnly() throws {
    var calls = 0
    var consumes = true
    var visibility: [Bool] = []
    let controller = DropdownController(
        moduleName: "Time", statusItem: nil, rootView: AnyView(Text("Time")), contentHeight: 100,
        usesAttachedPanel: true,
        primaryClickHandler: { calls += 1; return consumes },
        visibilityAction: { visibility.append($0) }, tickAction: {}, settingsAction: {}, quitAction: {}
    )

    controller.handleStatusItemClick(try #require(mouseEvent(.leftMouseUp)))
    #expect(calls == 1)
    #expect(visibility.isEmpty)

    controller.handleStatusItemClick(try #require(mouseEvent(.rightMouseUp)))
    controller.handleStatusItemClick(try #require(mouseEvent(.leftMouseUp, modifiers: [.control])))
    #expect(calls == 1)

    // A declined click falls through to the dropdown path, which needs an anchor to present.
    consumes = false
    controller.handleStatusItemClick(try #require(mouseEvent(.leftMouseUp)))
    #expect(calls == 2)
    #expect(visibility.isEmpty)
}
