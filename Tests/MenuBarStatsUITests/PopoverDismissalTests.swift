import AppKit
import Testing
@testable import MenuBarStatsUI

@MainActor
@Test("Popover remains navigable inside, dismisses on hover exit, and stops watching after close")
func hoverDismissal() {
    let monitor = PopoverDismissalMonitor()
    let root = NSRect(x: 100, y: 100, width: 300, height: 500)
    let detail = NSRect(x: 410, y: 100, width: 300, height: 500)
    var dismissals = 0
    monitor.start(containsPoint: { root.contains($0) || detail.contains($0) },
                  dismiss: { dismissals += 1 })
    let start = ProcessInfo.processInfo.systemUptime
    monitor.handleHover(at: NSPoint(x: 200, y: 200), time: start)
    monitor.handleHover(at: NSPoint(x: 405, y: 200), time: start + 0.1)
    #expect(dismissals == 0)
    monitor.handleHover(at: NSPoint(x: 500, y: 200), time: start + 0.2)
    monitor.handleHover(at: .zero, time: start + 0.9)
    #expect(dismissals == 0)
    monitor.handleHover(at: .zero, time: start + 1.1)
    #expect(dismissals == 1)
    monitor.handleClick(at: .zero)
    #expect(dismissals == 1)
}

@MainActor
@Test("Outside click dismisses immediately and inside clicks keep the popover open")
func outsideClickDismissal() {
    let monitor = PopoverDismissalMonitor()
    var dismissed = false
    monitor.start(containsPoint: { $0.x > 100 }, dismiss: { dismissed = true })
    monitor.handleClick(at: NSPoint(x: 200, y: 200))
    #expect(!dismissed)
    monitor.handleClick(at: .zero)
    #expect(dismissed)
    monitor.stop()
}

@MainActor
@Test("Manager-synthesized click outside the real item does not start hover dismissal before entry")
func managerPointerHandoff() {
    let monitor = PopoverDismissalMonitor()
    var dismissed = false
    monitor.start(containsPoint: { $0.x > 100 }, dismiss: { dismissed = true })
    let start = ProcessInfo.processInfo.systemUptime
    monitor.handleHover(at: .zero, time: start + 10)
    #expect(!dismissed)
    monitor.handleHover(at: NSPoint(x: 200, y: 200), time: start + 11)
    monitor.handleHover(at: .zero, time: start + 11.7)
    #expect(!dismissed)
    monitor.handleHover(at: .zero, time: start + 11.9)
    #expect(dismissed)
}
