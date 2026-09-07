import Foundation
import Testing
@testable import SystemSources

@Suite("Notification Center action bridge")
struct NotificationCenterActionBridgeTests {
    @Test("UUID matching accepts only complete identifiers")
    func exactIdentifierNormalization() {
        #expect(NotificationAccessibilityIdentity.normalizedUUID("00112233445566778899aabbccddeeff") ==
            "00112233445566778899AABBCCDDEEFF")
        #expect(NotificationAccessibilityIdentity.normalizedUUID("{00112233-4455-6677-8899-AABBCCDDEEFF}") ==
            "00112233445566778899AABBCCDDEEFF")
        #expect(NotificationAccessibilityIdentity.normalizedUUID(" 00112233-4455-6677-8899-aabbccddeeff \n") ==
            "00112233445566778899AABBCCDDEEFF")

        #expect(NotificationAccessibilityIdentity.normalizedUUID("prefix-00112233-4455-6677-8899-AABBCCDDEEFF") == nil)
        #expect(NotificationAccessibilityIdentity.normalizedUUID("00112233445566778899AABBCCDDEEF") == nil)
        #expect(NotificationAccessibilityIdentity.normalizedUUID("00112233445566778899AABBCCDDEEFG") == nil)
        #expect(NotificationAccessibilityIdentity.normalizedUUID("{00112233-4455-6677-8899-AABBCCDDEEFF") == nil)
    }

    @Test("a row must be the only exact UUID match")
    func uniqueExactMatch() {
        let identifier = "00112233445566778899AABBCCDDEEFF"
        let candidates = [
            ["com.example.app", "A title containing 00112233445566778899AABBCCDDEEFF is not an identifier"],
            ["00112233-4455-6677-8899-aabbccddeeff"],
            ["FFEEDDCCBBAA99887766554433221100"],
        ]
        #expect(NotificationAccessibilityIdentity.uniqueMatchingIndex(
            identifier: identifier,
            candidates: candidates
        ) == 1)
        #expect(NotificationAccessibilityIdentity.uniqueMatchingIndex(
            identifier: identifier,
            candidates: candidates + [[identifier]]
        ) == nil)
        #expect(NotificationAccessibilityIdentity.uniqueMatchingIndex(
            identifier: "not-a-uuid",
            candidates: candidates
        ) == nil)
    }

    @Test("an incomplete Accessibility scan never authorizes a match")
    func incompleteScan() {
        let identifier = "00112233445566778899AABBCCDDEEFF"
        #expect(NotificationAccessibilityIdentity.uniqueMatchingIndex(
            identifier: identifier,
            candidates: [[identifier]],
            scanCompleted: false
        ) == nil)
    }

    @Test("activation requires an advertised press on the exact row or its default button")
    func activationPlan() {
        #expect(NotificationAccessibilityAction.plan(
            for: .activate,
            rowActions: ["AXPress", "AXShowMenu"],
            defaultButtonActions: nil,
            closeButtonActions: nil
        ) == .rowPress)
        #expect(NotificationAccessibilityAction.plan(
            for: .activate,
            rowActions: ["AXShowMenu"],
            defaultButtonActions: ["AXPress"],
            closeButtonActions: nil
        ) == .defaultButtonPress)
        #expect(NotificationAccessibilityAction.plan(
            for: .activate,
            rowActions: ["Open"],
            defaultButtonActions: nil,
            closeButtonActions: nil
        ) == nil)
    }

    @Test("dismissal requires an advertised press on the exact row's close button")
    func dismissalPlan() {
        #expect(NotificationAccessibilityAction.plan(
            for: .dismiss,
            rowActions: ["AXPress"],
            defaultButtonActions: ["AXPress"],
            closeButtonActions: nil
        ) == nil)
        #expect(NotificationAccessibilityAction.plan(
            for: .dismiss,
            rowActions: [],
            defaultButtonActions: nil,
            closeButtonActions: ["AXPress"]
        ) == .closeButtonPress)
        #expect(NotificationAccessibilityAction.plan(
            for: .dismiss,
            rowActions: [],
            defaultButtonActions: nil,
            closeButtonActions: ["Clear All Notifications"]
        ) == nil)
    }

    @Test("bridge forwards one selected action and UUID to its adapter")
    func actionForwarding() async {
        let identifier = "00112233445566778899AABBCCDDEEFF"
        let notification = DeliveredNotification(
            id: identifier,
            applicationIdentifier: "com.example.app",
            title: "Example",
            subtitle: nil,
            body: nil,
            date: Date(timeIntervalSinceReferenceDate: 0)
        )
        let adapter = ExpectedActionAdapter(
            available: true,
            expectedAction: .dismiss,
            expectedIdentifier: identifier,
            result: .accepted
        )
        let bridge = NotificationCenterActionBridge(adapter: adapter)

        #expect(await bridge.isAvailable)
        #expect(await bridge.perform(.dismiss, for: notification) == .accepted)
        #expect(await bridge.perform(.activate, for: notification) == .failed)
        #expect(await bridge.diagnostics(for: [notification]) == "aggregate diagnostics")
    }
}

private struct ExpectedActionAdapter: NotificationCenterActionAdapting {
    let available: Bool
    let expectedAction: NotificationSystemAction
    let expectedIdentifier: String
    let result: NotificationSystemActionResult

    var isAvailable: Bool { available }

    func perform(
        _ action: NotificationSystemAction,
        notificationIdentifier: String
    ) -> NotificationSystemActionResult {
        guard Self.matches(action, expectedAction), notificationIdentifier == expectedIdentifier else { return .failed }
        return result
    }

    func diagnostics(notificationIdentifiers: [String]) -> String {
        notificationIdentifiers == [expectedIdentifier] ? "aggregate diagnostics" : "unexpected identifiers"
    }

    private static func matches(_ left: NotificationSystemAction, _ right: NotificationSystemAction) -> Bool {
        switch (left, right) {
        case (.activate, .activate), (.dismiss, .dismiss):
            true
        default:
            false
        }
    }
}
