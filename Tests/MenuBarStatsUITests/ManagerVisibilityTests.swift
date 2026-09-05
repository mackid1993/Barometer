import Testing
@testable import MenuBarStatsUI

@Test("Live renders do not override visibility controlled temporarily by a menu bar manager")
func managerVisibility() {
    var latch = StatusItemVisibilityLatch()
    #expect(latch.shouldApply(true) == false)
    #expect(latch.activate() == true)
    #expect(latch.shouldApply(true) == true)
    // Simulate repeated sampling and opening a dropdown after the manager has hidden the item.
    // The manager's observed isVisible must not become an input to Barometer's visibility policy.
    for _ in 0..<100 {
        #expect(latch.shouldApply(true) == false)
    }
    #expect(latch.shouldApply(false) == true)
    #expect(latch.shouldApply(false) == false)
    #expect(latch.shouldApply(true) == true)
}
