//
//  MenuBarAssessmentAssertion.swift
//  Barometer
//
//  Adapted from the assessment-mode assertion in Thaw's PlatformRuntimeKit
//  (https://github.com/thaw-app/Thaw), Copyright © 2026 Toni Förster, GNU GPLv3,
//  used with the permission of Thaw's maintainers. Barometer is licensed under the GNU GPLv3.
//

import Foundation
import ObjectiveC
import OSLog

/// Removes chosen system items from the menu bar through the menu bar's assessment mode.
///
/// macOS 26 and 27 draw the menu bar in MenuBarAgent, whose private `MenuBarClientCore` framework
/// lets a client hold an assessment-mode assertion: a configuration names which system items and
/// which third-party bundle identifiers stay on the bar, and the bar removes everything else while
/// the assertion is live. The system items are numbered; on macOS 27.0 the clock is 2, Wi-Fi is
/// 6, and Control Center is 8 (verified by removing one index at a time). Apple extras outside that
/// numbered set, such as AirDrop, Focus, Now Playing, and the user switcher, are removed whenever
/// any assertion is live; that is the cost Thaw documents, and Barometer inherits it.
///
/// This is the only type that touches the framework. It loads it lazily, reports `isAvailable`
/// when the classes exist, and never throws past its own error type.
@MainActor
public final class MenuBarAssessmentAssertion {
    /// Why an activation did not take.
    public enum Failure: Error, Equatable, Sendable {
        case unavailable
        case rejected(String)
        case timedOut
    }

    /// Numbered system items as MenuBarAgent counts them on macOS 27.0.
    public enum SystemItem: Int, CaseIterable, Sendable {
        case item0 = 0, item1, clock, item3, item4, item5, wifi, item7, controlCenter
    }

    private static let logger = Logger(subsystem: "com.barometer.app", category: "assessment")
    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore"
    private static let activateSelector = NSSelectorFromString("activateWithConfiguration:completionHandler:")
    private static let configureSelector = NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:")
    private static let invalidateSelector = NSSelectorFromString("invalidate")

    private static let classes: (configuration: AnyClass, assertion: AnyClass)? = {
        guard dlopen(frameworkPath, RTLD_NOW) != nil,
              let configuration = NSClassFromString("MBAssessmentModeConfiguration"),
              let assertion = NSClassFromString("MBAssessmentModeAssertion"),
              configuration.instancesRespond(to: configureSelector),
              assertion.instancesRespond(to: activateSelector),
              assertion.instancesRespond(to: invalidateSelector)
        else {
            logger.warning("menu bar assessment mode is unavailable on this macOS build")
            return nil
        }
        return (configuration, assertion)
    }()

    /// Whether this macOS build offers the assertion at all.
    public static var isAvailable: Bool { classes != nil }

    private var assertion: AnyObject?

    /// Whether an assertion is currently live.
    public private(set) var isActive = false

    public init() {}

    /// Every system index except the ones to remove.
    public nonisolated static func allowedSystemItems(removing removed: Set<SystemItem>) -> [Int] {
        SystemItem.allCases.filter { !removed.contains($0) }.map(\.rawValue)
    }

    /// Activates an assertion that keeps the given system items and third-party bundles and removes the rest.
    ///
    /// A previous assertion held by this object is invalidated first, so re-activating with a new
    /// allowlist is how the bar follows applications that launch or quit.
    public func activate(allowedSystemItems: [Int], allowedBundleIdentifiers: [String]) async throws(Failure) {
        guard let classes = Self.classes else { throw .unavailable }
        invalidate()
        let configuration = (classes.configuration.alloc() as AnyObject).perform(
            Self.configureSelector,
            with: allowedSystemItems.map { NSNumber(value: $0) } as NSArray,
            with: Array(Set(allowedBundleIdentifiers)).sorted() as NSArray
        )?.takeUnretainedValue()
        guard let configuration,
              let assertion = (classes.assertion.alloc() as AnyObject)
                  .perform(NSSelectorFromString("init"))?.takeUnretainedValue()
        else { throw .unavailable }

        let result: Result<Void, Failure> = await withCheckedContinuation { continuation in
            let gate = ContinuationGate()
            let completion: @convention(block) (Any?) -> Void = { error in
                guard gate.claim() else { return }
                if let error {
                    continuation.resume(returning: .failure(.rejected(String(describing: error))))
                } else {
                    continuation.resume(returning: .success(()))
                }
            }
            _ = assertion.perform(Self.activateSelector, with: configuration, with: completion)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                guard gate.claim() else { return }
                continuation.resume(returning: .failure(.timedOut))
            }
        }
        switch result {
        case .success:
            self.assertion = assertion
            isActive = true
            Self.logger.notice("assessment assertion active, system items \(allowedSystemItems, privacy: .public)")
        case let .failure(failure):
            _ = assertion.perform(Self.invalidateSelector)
            Self.logger.error("assessment assertion failed: \(String(describing: failure), privacy: .public)")
            throw failure
        }
    }

    /// Releases the assertion; the bar restores everything it removed.
    public func invalidate() {
        guard let assertion else { return }
        _ = assertion.perform(Self.invalidateSelector)
        self.assertion = nil
        isActive = false
        Self.logger.notice("assessment assertion released")
    }
}

/// One-shot claim shared by a completion block and its timeout.
private final class ContinuationGate: @unchecked Sendable {
    // A lock guards the single flag; that is the whole reason the class is marked unchecked.
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
