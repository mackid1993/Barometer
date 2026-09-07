import Testing
@testable import SystemSources

@Suite("MenuBarAssessmentAssertionTests")
struct MenuBarAssessmentAssertionTests {
    @Test("the clock's slot is 2 and removing it keeps the other eight system items")
    func allowlist() {
        #expect(MenuBarAssessmentAssertion.SystemItem.clock.rawValue == 2)
        #expect(MenuBarAssessmentAssertion.SystemItem.wifi.rawValue == 6)
        #expect(MenuBarAssessmentAssertion.SystemItem.controlCenter.rawValue == 8)
        #expect(MenuBarAssessmentAssertion.allowedSystemItems(removing: [.clock]) == [0, 1, 3, 4, 5, 6, 7, 8])
        #expect(MenuBarAssessmentAssertion.allowedSystemItems(removing: []).count == 9)
    }

    @Test("an inactive assertion invalidates quietly")
    @MainActor
    func inactive() {
        let assertion = MenuBarAssessmentAssertion()
        #expect(assertion.isActive == false)
        assertion.invalidate()
        #expect(assertion.isActive == false)
    }
}
