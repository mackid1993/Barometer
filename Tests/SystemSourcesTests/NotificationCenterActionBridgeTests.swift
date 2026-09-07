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

    @Test("only an individual banner can match a notification UUID")
    func individualBannerMatch() {
        let identifier = "00112233445566778899AABBCCDDEEFF"
        let candidates = [[identifier], [identifier], [identifier]]
        let subroles = [
            "AXNotificationCenterBannerStack",
            NotificationAccessibilityIdentity.bannerSubrole,
            "AXGroup",
        ]

        #expect(NotificationAccessibilityIdentity.uniqueIndividualNotificationMatchingIndex(
            identifier: identifier,
            candidates: candidates,
            subroles: subroles
        ) == 1)
        #expect(NotificationAccessibilityIdentity.uniqueIndividualNotificationMatchingIndex(
            identifier: identifier,
            candidates: [[identifier]],
            subroles: ["AXNotificationCenterBannerStack"]
        ) == nil)
        #expect(NotificationAccessibilityIdentity.uniqueIndividualNotificationMatchingIndex(
            identifier: identifier,
            candidates: [[identifier]],
            subroles: [],
            scanCompleted: true
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

    @Test("dismissal uses only an advertised Close action or the exact row's close button")
    func dismissalPlan() {
        let closeAction = "Name:Close\nTarget:0x0\nSelector:(null)"
        #expect(NotificationAccessibilityAction.plan(
            for: .dismiss,
            rowActions: ["AXPress", closeAction],
            rowActionDescriptions: [
                .init(name: "AXPress", description: "press"),
                .init(name: closeAction, description: "Close"),
            ],
            defaultButtonActions: nil,
            closeButtonActions: nil
        ) == .rowClose(closeAction))
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
        #expect(NotificationAccessibilityAction.plan(
            for: .dismiss,
            rowActions: [closeAction],
            rowActionDescriptions: [.init(name: closeAction, description: "Clear All")],
            defaultButtonActions: nil,
            closeButtonActions: nil
        ) == nil)
        #expect(NotificationAccessibilityAction.plan(
            for: .dismiss,
            rowActions: [closeAction, "different-close-action"],
            rowActionDescriptions: [
                .init(name: closeAction, description: "Close"),
                .init(name: "different-close-action", description: "Close"),
            ],
            defaultButtonActions: nil,
            closeButtonActions: nil
        ) == nil)
    }

    @Test("failed preparation prevents Accessibility dispatch")
    func failedPreparation() async {
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
        let bridge = NotificationCenterActionBridge(adapter: adapter, prepareAction: { false })

        #expect(await bridge.perform(.dismiss, for: notification) == .unavailable)
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
