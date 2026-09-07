import ApplicationServices
import CoreGraphics
import Darwin
import Foundation
import OSLog

/// An operation performed on one notification through macOS Notification Center.
public enum NotificationSystemAction: Sendable {
    /// Perform the notification's default action, equivalent to selecting it in Notification Center.
    case activate
    /// Dismiss only the selected notification.
    case dismiss
}

/// The result of asking macOS to perform a notification action.
public enum NotificationSystemActionResult: Equatable, Sendable {
    /// Notification Center accepted the Accessibility action.
    case accepted
    /// No safe action could be dispatched.
    case unavailable
    /// Dispatch was attempted, but Notification Center did not accept it.
    case failed
}

/// Performs actions on notifications that belong to other applications.
///
/// Apple's public UserNotifications API exposes only notifications delivered by the calling application. This
/// bridge therefore uses the public macOS Accessibility client API against Notification Center. It never requests
/// Accessibility access, writes Notification Center's database, or uses its private notification service.
///
/// A row must expose exactly the requested notification UUID through an identifier attribute. Titles, application
/// names, dates, and notification text are deliberately not used for matching. The action must also be advertised
/// by that row through Accessibility before it is performed.
public actor NotificationCenterActionBridge {
    /// The process-wide notification action bridge.
    public static let shared = NotificationCenterActionBridge()

    private let adapter: any NotificationCenterActionAdapting
    private let prepareAction: @Sendable () async -> Bool

    /// Creates a bridge to the system Notification Center.
    public init(prepareAction: @escaping @Sendable () async -> Bool = { true }) {
        adapter = NotificationCenterAccessibilityAdapter()
        self.prepareAction = prepareAction
    }

    init(
        adapter: any NotificationCenterActionAdapting,
        prepareAction: @escaping @Sendable () async -> Bool = { true }
    ) {
        self.adapter = adapter
        self.prepareAction = prepareAction
    }

    /// Whether Notification Center is running and this process already has Accessibility access.
    public var isAvailable: Bool {
        adapter.isAvailable
    }

    /// Retains short-lived action handles for uniquely identified individual notification rows currently exposed by
    /// Notification Center. This performs no action and drops handles absent from the authoritative notification set.
    public func primeActions(for notifications: [DeliveredNotification]) {
        adapter.primeActions(notificationIdentifiers: notifications.map(\.id))
    }

    /// Performs an action on the one Notification Center row whose identifier exactly matches the notification UUID.
    public func perform(
        _ action: NotificationSystemAction,
        for notification: DeliveredNotification
    ) async -> NotificationSystemActionResult {
        guard !Task.isCancelled else { return .unavailable }
        guard await prepareAction() else { return .unavailable }
        guard !Task.isCancelled else { return .unavailable }

        // Notification Center publishes its Accessibility rows after its opening animation begins. Retry only
        // pre-dispatch failures; accepted and failed results both mean an action was attempted and must never repeat.
        let retryDelays: [Duration] = [.zero, .milliseconds(120), .milliseconds(240), .milliseconds(360)]
        for delay in retryDelays {
            guard !Task.isCancelled else { return .unavailable }
            if delay != .zero {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return .unavailable }
            }
            let result = adapter.perform(action, notificationIdentifier: notification.id)
            if result != .unavailable { return result }
        }
        return .unavailable
    }

    /// Returns aggregate, read-only diagnostics without exposing notification contents or identifiers.
    public func diagnostics(for notifications: [DeliveredNotification]) async -> String {
        adapter.diagnostics(notificationIdentifiers: notifications.map(\.id))
    }
}

// MARK: - Adapter

protocol NotificationCenterActionAdapting {
    var isAvailable: Bool { get }

    func perform(
        _ action: NotificationSystemAction,
        notificationIdentifier: String
    ) -> NotificationSystemActionResult

    func primeActions(notificationIdentifiers: [String])

    func diagnostics(notificationIdentifiers: [String]) -> String
}

extension NotificationCenterActionAdapting {
    func primeActions(notificationIdentifiers: [String]) {}
}

private final class NotificationCenterAccessibilityAdapter: NotificationCenterActionAdapting {
    private static let executablePath =
        "/System/Library/CoreServices/NotificationCenter.app/Contents/MacOS/NotificationCenter"
    private static let maximumElementCount = 4_096
    private static let maximumTreeDepth = 20
    private static let messageTimeout: Float = 0.15
    private static let totalTimeout: TimeInterval = 1
    private static let cacheLifetime: TimeInterval = 5 * 60
    private static let maximumCachedElementCount = 256

    private let logger = Logger(subsystem: "com.barometer.app", category: "notification-actions")
    private var cachedElements: [String: CachedElement] = [:]
    private var cachedProcessIdentifier: pid_t?

    private struct CachedElement {
        let element: AXUIElement
        let capturedAt: TimeInterval
    }

    var isAvailable: Bool {
        AXIsProcessTrusted() && Self.notificationCenterProcessIdentifier() != nil
    }

    func primeActions(notificationIdentifiers: [String]) {
        let requestedIdentifiers = Set(
            notificationIdentifiers.compactMap(NotificationAccessibilityIdentity.normalizedUUID)
        )
        let now = ProcessInfo.processInfo.systemUptime
        guard AXIsProcessTrusted(), let processIdentifier = Self.notificationCenterProcessIdentifier() else {
            cachedElements.removeAll()
            cachedProcessIdentifier = nil
            return
        }
        pruneCache(processIdentifier: processIdentifier, retaining: requestedIdentifiers, now: now)
        guard !requestedIdentifiers.isEmpty else { return }

        let application = AXUIElementCreateApplication(processIdentifier)
        guard AXUIElementSetMessagingTimeout(application, Self.messageTimeout) == .success else { return }
        let deadline = now + Self.totalTimeout
        guard let windows = elementsAttribute(kAXWindowsAttribute, of: application, deadline: deadline) else { return }
        let scan = scanElements(under: windows, deadline: deadline)
        guard scan.completed else { return }
        for identifier in requestedIdentifiers {
            guard ProcessInfo.processInfo.systemUptime < deadline else { break }
            let matches = matchingElementIndices(identifier, in: scan)
            if matches.count > 1 {
                cachedElements.removeValue(forKey: identifier)
            } else if let index = matches.first {
                cachedElements[identifier] = CachedElement(element: scan.elements[index], capturedAt: now)
            }
        }
        trimCacheToLimit()
    }

    func perform(
        _ action: NotificationSystemAction,
        notificationIdentifier: String
    ) -> NotificationSystemActionResult {
        guard AXIsProcessTrusted() else {
            logger.info("notification action unavailable because Accessibility access is not granted")
            return .unavailable
        }
        guard let processIdentifier = Self.notificationCenterProcessIdentifier() else {
            logger.info("notification action unavailable because Notification Center is not running")
            return .unavailable
        }
        guard let normalizedIdentifier = NotificationAccessibilityIdentity.normalizedUUID(notificationIdentifier) else {
            logger.error("notification action unavailable because the requested identifier is not a UUID")
            return .unavailable
        }
        let now = ProcessInfo.processInfo.systemUptime
        pruneCache(processIdentifier: processIdentifier, retaining: nil, now: now)

        let application = AXUIElementCreateApplication(processIdentifier)
        guard AXUIElementSetMessagingTimeout(application, Self.messageTimeout) == .success else {
            logger.info("notification action unavailable because the Accessibility timeout could not be set")
            return .unavailable
        }
        let deadline = ProcessInfo.processInfo.systemUptime + Self.totalTimeout
        guard let windows = elementsAttribute(kAXWindowsAttribute, of: application, deadline: deadline) else {
            logger.info("notification action unavailable because Notification Center windows could not be read")
            return .unavailable
        }
        let scan = scanElements(under: windows, deadline: deadline)
        guard scan.completed else {
            logger.info("notification action unavailable because the Accessibility scan did not complete")
            return .unavailable
        }
        let currentMatches = matchingElementIndices(normalizedIdentifier, in: scan)
        guard currentMatches.count <= 1 else {
            cachedElements.removeValue(forKey: normalizedIdentifier)
            logger.info("notification action unavailable because multiple Accessibility rows matched the UUID")
            return .unavailable
        }
        var usedCachedElement = false
        var row = currentMatches.first.map { scan.elements[$0] }
        if let row {
            cachedElements[normalizedIdentifier] = CachedElement(element: row, capturedAt: now)
            trimCacheToLimit()
        }
        if row == nil, let cached = cachedElements[normalizedIdentifier] {
            guard cachedElementStillMatches(cached.element, identifier: normalizedIdentifier, deadline: deadline) else {
                cachedElements.removeValue(forKey: normalizedIdentifier)
                logger.info("notification action unavailable because the cached Accessibility row is stale")
                return .unavailable
            }
            row = cached.element
            usedCachedElement = true
        }
        guard let row else {
            logger.info("notification action unavailable because no unique Accessibility row matched the UUID")
            return .unavailable
        }
        guard usedCachedElement || cachedElementStillMatches(
            row, identifier: normalizedIdentifier, deadline: deadline
        ) else {
            cachedElements.removeValue(forKey: normalizedIdentifier)
            logger.info("notification action unavailable because the live row identity changed or was conflicting")
            return .unavailable
        }
        guard let target = actionTarget(for: action, row: row, deadline: deadline) else {
            cachedElements.removeValue(forKey: normalizedIdentifier)
            logger.info("notification action unavailable because the matched row did not advertise a safe action")
            return .unavailable
        }
        guard ProcessInfo.processInfo.systemUptime < deadline else {
            logger.info("notification action unavailable because the Accessibility deadline expired")
            return .unavailable
        }
        guard Self.setMessageTimeout(for: target.element) else {
            cachedElements.removeValue(forKey: normalizedIdentifier)
            logger.info("notification action unavailable because the action timeout could not be set")
            return .unavailable
        }

        // Reaching dispatch consumes the handle regardless of success so an accepted action is never repeated.
        cachedElements.removeValue(forKey: normalizedIdentifier)
        let error = AXUIElementPerformAction(target.element, target.actionName as CFString)
        guard error == .success else {
            logger.error("notification Accessibility action failed with error \(error.rawValue, privacy: .public)")
            return .failed
        }
        let rowSource = usedCachedElement ? "cached" : "live"
        logger.info("notification Accessibility action accepted using \(rowSource, privacy: .public) native row")
        return .accepted
    }

    private func cachedElementStillMatches(
        _ element: AXUIElement,
        identifier: String,
        deadline: TimeInterval
    ) -> Bool {
        guard ProcessInfo.processInfo.systemUptime < deadline,
              Self.setMessageTimeout(for: element),
              stringAttribute(kAXSubroleAttribute, of: element) == NotificationAccessibilityIdentity.bannerSubrole,
              let identifiers = identifierValues(of: element, deadline: deadline)
        else { return false }
        let normalized = Set(identifiers.compactMap(NotificationAccessibilityIdentity.normalizedUUID))
        return normalized == Set([identifier])
    }

    private func pruneCache(
        processIdentifier: pid_t,
        retaining identifiers: Set<String>?,
        now: TimeInterval
    ) {
        if cachedProcessIdentifier != processIdentifier {
            cachedElements.removeAll()
            cachedProcessIdentifier = processIdentifier
        }
        cachedElements = cachedElements.filter { identifier, cached in
            now - cached.capturedAt <= Self.cacheLifetime && (identifiers?.contains(identifier) ?? true)
        }
    }

    private func trimCacheToLimit() {
        guard cachedElements.count > Self.maximumCachedElementCount else { return }
        let overflow = cachedElements.count - Self.maximumCachedElementCount
        for identifier in cachedElements.sorted(by: { $0.value.capturedAt < $1.value.capturedAt }).prefix(overflow) {
            cachedElements.removeValue(forKey: identifier.key)
        }
    }

    func diagnostics(notificationIdentifiers: [String]) -> String {
        let trusted = AXIsProcessTrusted()
        let processIdentifier = Self.notificationCenterProcessIdentifier()
        guard trusted, let processIdentifier else {
            return Self.diagnosticDescription(
                trusted: trusted,
                processPresent: processIdentifier != nil,
                scanCompleted: false,
                candidateCount: 0,
                exactMatchCount: 0,
                activationActionCount: 0,
                dismissalActionCount: 0
            )
        }

        let application = AXUIElementCreateApplication(processIdentifier)
        guard AXUIElementSetMessagingTimeout(application, Self.messageTimeout) == .success else {
            return Self.diagnosticDescription(
                trusted: true,
                processPresent: true,
                scanCompleted: false,
                candidateCount: 0,
                exactMatchCount: 0,
                activationActionCount: 0,
                dismissalActionCount: 0
            )
        }
        let deadline = ProcessInfo.processInfo.systemUptime + Self.totalTimeout
        guard let windows = elementsAttribute(kAXWindowsAttribute, of: application, deadline: deadline) else {
            return Self.diagnosticDescription(
                trusted: true,
                processPresent: true,
                scanCompleted: false,
                candidateCount: 0,
                exactMatchCount: 0,
                activationActionCount: 0,
                dismissalActionCount: 0
            )
        }
        let scan = scanElements(under: windows, deadline: deadline)
        var completed = scan.completed
        var exactMatchCount = 0
        var activationActionCount = 0
        var dismissalActionCount = 0
        if completed {
            for identifier in notificationIdentifiers {
                guard ProcessInfo.processInfo.systemUptime < deadline else {
                    completed = false
                    break
                }
                guard let row = matchingElement(identifier, in: scan) else { continue }
                exactMatchCount += 1
                if actionTarget(for: .activate, row: row, deadline: deadline) != nil {
                    activationActionCount += 1
                }
                if actionTarget(for: .dismiss, row: row, deadline: deadline) != nil {
                    dismissalActionCount += 1
                }
                guard ProcessInfo.processInfo.systemUptime < deadline else {
                    completed = false
                    break
                }
            }
        }
        return Self.diagnosticDescription(
            trusted: true,
            processPresent: true,
            scanCompleted: completed,
            candidateCount: scan.identifierCandidates.count,
            exactMatchCount: exactMatchCount,
            activationActionCount: activationActionCount,
            dismissalActionCount: dismissalActionCount
        )
    }

    private struct AccessibilityScan {
        var elements: [AXUIElement] = []
        var identifierCandidates: [[String]] = []
        var subroles: [String?] = []
        var completed = true
    }

    private func scanElements(under roots: [AXUIElement], deadline: TimeInterval) -> AccessibilityScan {
        var stack = roots.map { (element: $0, depth: 0) }
        var scan = AccessibilityScan()
        var visitedCount = 0

        while let current = stack.popLast() {
            guard visitedCount < Self.maximumElementCount,
                  ProcessInfo.processInfo.systemUptime < deadline
            else {
                scan.completed = false
                break
            }
            visitedCount += 1
            guard Self.setMessageTimeout(for: current.element),
                  let identifiers = identifierValues(of: current.element, deadline: deadline),
                  let children = elementsAttribute(kAXChildrenAttribute, of: current.element, deadline: deadline)
            else {
                scan.completed = false
                break
            }
            if !identifiers.isEmpty {
                scan.elements.append(current.element)
                scan.identifierCandidates.append(identifiers)
                scan.subroles.append(stringAttribute(kAXSubroleAttribute, of: current.element))
            }
            guard current.depth < Self.maximumTreeDepth else {
                if !children.isEmpty { scan.completed = false }
                if !scan.completed { break }
                continue
            }
            for child in children {
                stack.append((child, current.depth + 1))
            }
        }
        if !stack.isEmpty { scan.completed = false }
        return scan
    }

    private func matchingElement(_ identifier: String, in scan: AccessibilityScan) -> AXUIElement? {
        guard let index = NotificationAccessibilityIdentity.uniqueIndividualNotificationMatchingIndex(
            identifier: identifier,
            candidates: scan.identifierCandidates,
            subroles: scan.subroles,
            scanCompleted: scan.completed
        ) else {
            return nil
        }
        return scan.elements[index]
    }

    private func matchingElementIndices(_ identifier: String, in scan: AccessibilityScan) -> [Int] {
        guard scan.completed,
              let requested = NotificationAccessibilityIdentity.normalizedUUID(identifier)
        else { return [] }
        return scan.identifierCandidates.indices.filter { index in
            scan.subroles[index] == NotificationAccessibilityIdentity.bannerSubrole
                && scan.identifierCandidates[index].contains {
                    NotificationAccessibilityIdentity.normalizedUUID($0) == requested
                }
        }
    }

    private func identifierValues(of element: AXUIElement, deadline: TimeInterval) -> [String]? {
        guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
        var namesValue: CFArray?
        guard AXUIElementCopyAttributeNames(element, &namesValue) == .success,
              let names = namesValue as? [String]
        else {
            return nil
        }
        var identifiers: [String] = []
        for name in names where name.localizedCaseInsensitiveContains("identifier") {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
            if error == .noValue { continue }
            guard error == .success else { return nil }
            if let identifier = value as? String { identifiers.append(identifier) }
        }
        return identifiers
    }

    private func actionTarget(
        for action: NotificationSystemAction,
        row: AXUIElement,
        deadline: TimeInterval
    ) -> (element: AXUIElement, actionName: String)? {
        guard ProcessInfo.processInfo.systemUptime < deadline, Self.setMessageTimeout(for: row) else { return nil }
        guard stringAttribute(kAXSubroleAttribute, of: row) == NotificationAccessibilityIdentity.bannerSubrole else {
            return nil
        }
        switch action {
        case .activate:
            let rowActions = advertisedActions(of: row, deadline: deadline)
            let defaultButton = rowActions.contains(kAXPressAction as String)
                ? nil
                : elementAttribute(kAXDefaultButtonAttribute, of: row, deadline: deadline)
            let plan = NotificationAccessibilityAction.plan(
                for: action,
                rowActions: rowActions,
                defaultButtonActions: defaultButton.map { advertisedActions(of: $0, deadline: deadline) },
                closeButtonActions: nil
            )
            switch plan {
            case .rowPress:
                return (row, kAXPressAction as String)
            case .defaultButtonPress:
                return defaultButton.map { ($0, kAXPressAction as String) }
            default:
                return nil
            }
        case .dismiss:
            let describedRowActions = advertisedActionDescriptions(of: row, deadline: deadline)
            let closeButton = elementAttribute(kAXCloseButtonAttribute, of: row, deadline: deadline)
            let plan = NotificationAccessibilityAction.plan(
                for: action,
                rowActions: describedRowActions.map(\.name),
                rowActionDescriptions: describedRowActions,
                localizedCloseDescription: Self.localizedCloseDescription,
                defaultButtonActions: nil,
                closeButtonActions: closeButton.map { advertisedActions(of: $0, deadline: deadline) }
            )
            switch plan {
            case let .rowClose(actionName):
                return (row, actionName)
            case .closeButtonPress:
                return closeButton.map { ($0, kAXPressAction as String) }
            default:
                return nil
            }
        }
    }

    private func advertisedActionDescriptions(
        of element: AXUIElement,
        deadline: TimeInterval
    ) -> [NotificationAccessibilityAction.AdvertisedAction] {
        advertisedActions(of: element, deadline: deadline).compactMap { actionName in
            guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            var descriptionValue: CFString?
            guard AXUIElementCopyActionDescription(element, actionName as CFString, &descriptionValue) == .success,
                  let descriptionValue
            else {
                return nil
            }
            return NotificationAccessibilityAction.AdvertisedAction(
                name: actionName,
                description: descriptionValue as String
            )
        }
    }

    private func advertisedActions(of element: AXUIElement, deadline: TimeInterval) -> [String] {
        guard ProcessInfo.processInfo.systemUptime < deadline, Self.setMessageTimeout(for: element) else { return [] }
        var actionsValue: CFArray?
        guard AXUIElementCopyActionNames(element, &actionsValue) == .success else { return [] }
        return actionsValue as? [String] ?? []
    }

    private func elementsAttribute(
        _ name: String,
        of element: AXUIElement,
        deadline: TimeInterval
    ) -> [AXUIElement]? {
        guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        if error == .attributeUnsupported || error == .noValue { return [] }
        guard error == .success else { return nil }
        return value as? [AXUIElement]
    }

    private func elementAttribute(_ name: String, of element: AXUIElement, deadline: TimeInterval) -> AXUIElement? {
        guard ProcessInfo.processInfo.systemUptime < deadline,
              let value = valueAttribute(name, of: element),
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func valueAttribute(_ name: String, of element: AXUIElement) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func stringAttribute(_ name: String, of element: AXUIElement) -> String? {
        valueAttribute(name, of: element) as? String
    }

    private static func setMessageTimeout(for element: AXUIElement) -> Bool {
        AXUIElementSetMessagingTimeout(element, messageTimeout) == .success
    }

    private static let localizedCloseDescription: String = {
        guard let bundle = Bundle(path: "/System/Library/CoreServices/NotificationCenter.app") else { return "Close" }
        return bundle.localizedString(forKey: "Close", value: "Close", table: nil)
    }()

    private static func diagnosticDescription(
        trusted: Bool,
        processPresent: Bool,
        scanCompleted: Bool,
        candidateCount: Int,
        exactMatchCount: Int,
        activationActionCount: Int,
        dismissalActionCount: Int
    ) -> String {
        """
        Accessibility trusted: \(trusted)
        Notification Center process present: \(processPresent)
        Accessibility scan completed: \(scanCompleted)
        Identifier candidates: \(candidateCount)
        Exact UUID matches: \(exactMatchCount)
        Default actions available: \(activationActionCount)
        Dismiss actions available: \(dismissalActionCount)
        """
    }

    private static func notificationCenterProcessIdentifier() -> pid_t? {
        guard let windowInfo = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let processIdentifiers = Set(windowInfo.compactMap { window -> pid_t? in
            guard let number = window[kCGWindowOwnerPID as String] as? NSNumber else { return nil }
            return pid_t(number.int32Value)
        })
        return processIdentifiers.first(where: { executablePath(for: $0) == executablePath })
    }

    private static func executablePath(for processIdentifier: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(processIdentifier, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let bytes = buffer.prefix(Int(length)).prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}

// MARK: - Exact identity

enum NotificationAccessibilityIdentity {
    static let bannerSubrole = "AXNotificationCenterBanner"

    /// Normalizes only UUID punctuation and letter case. It never extracts a UUID from surrounding text.
    static func normalizedUUID(_ value: String) -> String? {
        var candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.first == "{", candidate.last == "}" {
            candidate.removeFirst()
            candidate.removeLast()
        }
        candidate.removeAll(where: { $0 == "-" })
        guard candidate.count == 32, candidate.allSatisfy(\.isHexDigit) else { return nil }
        return candidate.uppercased()
    }

    static func uniqueMatchingIndex(
        identifier: String,
        candidates: [[String]],
        scanCompleted: Bool = true
    ) -> Int? {
        guard scanCompleted else { return nil }
        guard let requested = normalizedUUID(identifier) else { return nil }
        let matches = candidates.indices.filter { index in
            candidates[index].contains(where: { normalizedUUID($0) == requested })
        }
        return matches.count == 1 ? matches[0] : nil
    }

    static func uniqueIndividualNotificationMatchingIndex(
        identifier: String,
        candidates: [[String]],
        subroles: [String?],
        scanCompleted: Bool = true
    ) -> Int? {
        guard candidates.count == subroles.count else { return nil }
        let eligibleCandidates = candidates.indices.map { index in
            subroles[index] == bannerSubrole ? candidates[index] : []
        }
        return uniqueMatchingIndex(
            identifier: identifier,
            candidates: eligibleCandidates,
            scanCompleted: scanCompleted
        )
    }
}

enum NotificationAccessibilityAction {
    struct AdvertisedAction: Equatable {
        let name: String
        let description: String
    }

    enum Plan: Equatable {
        case rowPress
        case rowClose(String)
        case defaultButtonPress
        case closeButtonPress
    }

    static func plan(
        for action: NotificationSystemAction,
        rowActions: [String],
        rowActionDescriptions: [AdvertisedAction] = [],
        localizedCloseDescription: String = "Close",
        defaultButtonActions: [String]?,
        closeButtonActions: [String]?
    ) -> Plan? {
        let press = kAXPressAction as String
        switch action {
        case .activate where rowActions.contains(press):
            return .rowPress
        case .activate where defaultButtonActions?.contains(press) == true:
            return .defaultButtonPress
        case .dismiss:
            let closeActions = rowActionDescriptions.filter {
                $0.description == localizedCloseDescription && rowActions.contains($0.name)
            }
            if closeActions.count == 1 {
                return .rowClose(closeActions[0].name)
            }
            if closeButtonActions?.contains(press) == true {
                return .closeButtonPress
            }
            return nil
        default:
            return nil
        }
    }
}
