import Darwin
import Foundation
import Intents
import OSLog

/// One user-configured Focus mode exposed by macOS.
public struct FocusMode: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let symbolName: String?

    /// Creates a Focus mode from its stable system identifier and display metadata.
    public init(id: String, name: String, symbolName: String? = nil) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
    }
}

/// Current Focus state and the modes macOS permits the user to select.
public enum FocusSnapshot: Equatable, Sendable {
    /// Neither the private service nor an already-authorized public Focus status is readable.
    case unavailable
    /// Focus is off.
    case inactive(availableModes: [FocusMode])
    /// Focus is on. The mode is nil when the public API proves activity but withholds its identity.
    case active(mode: FocusMode?, availableModes: [FocusMode])

    /// Whether Focus is currently active, when state is available.
    public var isActive: Bool? {
        switch self {
        case .unavailable: nil
        case .inactive: false
        case .active: true
        }
    }

    /// Active mode when macOS exposes its identity.
    public var activeMode: FocusMode? {
        guard case let .active(mode, _) = self else { return nil }
        return mode
    }

    /// Modes available for explicit selection.
    public var availableModes: [FocusMode] {
        switch self {
        case .unavailable: []
        case let .inactive(modes), let .active(_, modes): modes
        }
    }
}

/// Result of a user-requested Focus change.
public enum FocusControlResult: Equatable, Sendable {
    case applied
    case unavailable
    case failed
}

/// Reads and controls Focus through Apple's DoNotDisturb service when the process is allowed to use it.
///
/// The public Intents API is a read-only fallback. It is consulted only when the user has already
/// authorized Focus status sharing; this type never requests permission. That API exposes activity
/// but deliberately withholds the active mode's identity.
public actor FocusSource {
    private let runtime: DoNotDisturbRuntime?
    private let publicStatus: @Sendable () -> FocusSnapshot
    private let logger = Logger(subsystem: "com.barometer.app", category: "focus")

    /// Creates a source over the installed system framework.
    public init() {
        runtime = DoNotDisturbRuntime(clientIdentifier: "com.barometer.app")
        publicStatus = Self.currentPublicStatus
    }

    /// Whether current Focus state is readable without requesting authorization.
    public var isAvailable: Bool {
        read() != .unavailable
    }

    /// Reads the current state without requesting Focus authorization.
    public func read() -> FocusSnapshot {
        if let runtime {
            switch runtime.read() {
            case let .success(snapshot): return snapshot
            case let .failure(message):
                logger.debug("DoNotDisturb read unavailable: \(message, privacy: .public)")
            }
        }
        return publicStatus()
    }

    /// Activates a mode selected by the user.
    public func activate(_ mode: FocusMode) -> FocusControlResult {
        guard let runtime else { return .unavailable }
        return runtime.activate(modeIdentifier: mode.id)
    }

    /// Turns off the current Focus at the user's request.
    public func deactivate() -> FocusControlResult {
        guard let runtime else { return .unavailable }
        return runtime.deactivate()
    }

    static func publicSnapshot(
        authorizationStatus: INFocusStatusAuthorizationStatus,
        isFocused: Bool?
    ) -> FocusSnapshot {
        guard authorizationStatus == .authorized, let isFocused else { return .unavailable }
        return isFocused ? .active(mode: nil, availableModes: []) : .inactive(availableModes: [])
    }

    private static func currentPublicStatus() -> FocusSnapshot {
        let center = INFocusStatusCenter.default
        return publicSnapshot(
            authorizationStatus: center.authorizationStatus,
            isFocused: center.focusStatus.isFocused
        )
    }
}

// MARK: - Private framework boundary

/// The only type that loads or calls the private DoNotDisturb framework.
private final class DoNotDisturbRuntime {
    private static let frameworkPath = "/System/Library/PrivateFrameworks/DoNotDisturb.framework/DoNotDisturb"

    private let service: NSObject

    init?(clientIdentifier: String) {
        guard dlopen(Self.frameworkPath, RTLD_NOW) != nil,
              let serviceType = NSClassFromString("DNDModeSelectionService") as? NSObject.Type
        else {
            return nil
        }
        let selector = NSSelectorFromString("serviceForClientIdentifier:")
        guard serviceType.responds(to: selector),
              let service = serviceType.perform(selector, with: clientIdentifier)?.takeUnretainedValue() as? NSObject
        else {
            return nil
        }
        self.service = service
    }

    func read() -> RuntimeReadResult {
        let modesResult = objectWithError(selectorName: "availableModesWithError:")
        guard modesResult.error == nil, let array = modesResult.value as? NSArray else {
            return .failure(modesResult.error?.localizedDescription ?? "available modes were not returned")
        }
        let objects = array.compactMap { $0 as? NSObject }
        let modes = objects.compactMap(Self.mode(from:))

        let assertionResult = objectWithError(selectorName: "activeModeAssertionWithError:")
        guard assertionResult.error == nil else {
            return .failure(assertionResult.error?.localizedDescription ?? "active mode was not returned")
        }
        guard let assertion = assertionResult.value else {
            return .success(.inactive(availableModes: modes))
        }
        guard let details = Self.objectProperty("details", of: assertion),
              let identifier = Self.stringProperty("modeIdentifier", of: details)
        else {
            return .failure("active assertion had no mode identifier")
        }
        return .success(.active(mode: modes.first { $0.id == identifier }, availableModes: modes))
    }

    func activate(modeIdentifier: String) -> FocusControlResult {
        guard let lifetimeType = NSClassFromString("DNDModeAssertionLifetime") as? NSObject.Type,
              let detailsType = NSClassFromString("DNDModeAssertionDetails") as? NSObject.Type,
              let lifetime = Self.classObject(lifetimeType, selectorName: "lifetimeForUserRequest"),
              let details = Self.classObject(
                  detailsType,
                  selectorName: "userRequestedAssertionDetailsWithIdentifier:modeIdentifier:lifetime:",
                  arguments: [UUID().uuidString as NSString, modeIdentifier as NSString, lifetime]
              )
        else {
            return .unavailable
        }
        return boolWithObjectAndError(selectorName: "activateModeWithDetails:error:", object: details)
    }

    func deactivate() -> FocusControlResult {
        let assertionResult = objectWithError(selectorName: "activeModeAssertionWithError:")
        guard assertionResult.error == nil else { return .failed }
        guard let assertion = assertionResult.value else { return .applied }
        guard let identifier = Self.objectProperty("UUID", of: assertion) else { return .failed }
        return boolWithObjectAndError(selectorName: "invalidateModeAssertionWithUUID:error:", object: identifier)
    }

    private func objectWithError(selectorName: String) -> (value: NSObject?, error: NSError?) {
        let selector = NSSelectorFromString(selectorName)
        guard service.responds(to: selector), let implementation = service.method(for: selector) else {
            return (nil, NSError(domain: "FocusSource", code: 1))
        }
        typealias Function = @convention(c) (
            AnyObject,
            Selector,
            AutoreleasingUnsafeMutablePointer<NSError?>?
        ) -> Unmanaged<AnyObject>?
        let function = unsafeBitCast(implementation, to: Function.self)
        var error: NSError?
        let value = function(service, selector, &error)?.takeUnretainedValue() as? NSObject
        return (value, error)
    }

    private func boolWithObjectAndError(selectorName: String, object: NSObject) -> FocusControlResult {
        let selector = NSSelectorFromString(selectorName)
        guard service.responds(to: selector), let implementation = service.method(for: selector) else {
            return .unavailable
        }
        typealias Function = @convention(c) (
            AnyObject,
            Selector,
            AnyObject,
            AutoreleasingUnsafeMutablePointer<NSError?>?
        ) -> Bool
        let function = unsafeBitCast(implementation, to: Function.self)
        var error: NSError?
        return function(service, selector, object, &error) && error == nil ? .applied : .failed
    }

    private static func mode(from object: NSObject) -> FocusMode? {
        guard let identifier = stringProperty("modeIdentifier", of: object),
              let name = stringProperty("name", of: object)
        else {
            return nil
        }
        return FocusMode(id: identifier, name: name, symbolName: stringProperty("symbolImageName", of: object))
    }

    private static func stringProperty(_ name: String, of object: NSObject) -> String? {
        guard let value = objectProperty(name, of: object) as? NSString else { return nil }
        let text = (value as String).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func objectProperty(_ name: String, of object: NSObject) -> NSObject? {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue() as? NSObject
    }

    private static func classObject(
        _ type: NSObject.Type,
        selectorName: String,
        arguments: [NSObject] = []
    ) -> NSObject? {
        let selector = NSSelectorFromString(selectorName)
        guard arguments.count <= 3,
              let method = class_getClassMethod(type, selector)
        else {
            return nil
        }
        let implementation = method_getImplementation(method)
        switch arguments.count {
        case 0:
            typealias Function = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
            return unsafeBitCast(implementation, to: Function.self)(type, selector)?.takeUnretainedValue()
                as? NSObject
        case 3:
            typealias Function = @convention(c) (
                AnyObject, Selector, AnyObject, AnyObject, AnyObject
            ) -> Unmanaged<AnyObject>?
            return unsafeBitCast(implementation, to: Function.self)(
                type, selector, arguments[0], arguments[1], arguments[2]
            )?.takeUnretainedValue() as? NSObject
        default:
            return nil
        }
    }
}

private enum RuntimeReadResult {
    case success(FocusSnapshot)
    case failure(String)
}
