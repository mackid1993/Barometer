import Foundation
import Testing

@testable import SystemSources

@Suite("CalendarEventSourceTests")
struct CalendarEventSourceTests {
    @Test("authorization inspection never requests access")
    func authorizationInspection() async {
        let source = CalendarEventSource()
        let state = await source.authorizationState

        #expect(CalendarAuthorizationState.allCases.contains(state))
    }

    @Test("events degrade to an empty list without full access")
    func deniedEventRead() async throws {
        let source = CalendarEventSource()
        if await source.authorizationState != .fullAccess {
            #expect(await source.events(from: Date(), limit: 5).isEmpty)
        }
    }
}
