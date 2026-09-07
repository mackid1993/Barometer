//
//  SystemClockHider.swift
//  Barometer
//
//  Follows SystemClockHider.swift and SystemClockCover.swift in Thaw
//  (https://github.com/thaw-app/Thaw), Copyright © 2026 Toni Förster, GNU GPLv3,
//  used with the permission of Thaw's maintainers. Barometer is licensed under the GNU GPLv3.
//

import AppKit
import Observation
import OSLog
import SystemSources

/// Removes the macOS clock from the menu bar so Barometer's clock can take its place.
///
/// The clock is a MenuBarAgent child, and the one thing that takes it off the bar is the menu
/// bar's assessment-mode assertion, whose numbered system-item allowlist has a slot for the clock
/// alone. Leaving that slot out removes the clock and reclaims its width while Control Center,
/// Wi-Fi, and the rest stay. Every running application's bundle identifier is allowed, and the
/// allowlist is re-applied when applications launch or quit so nothing else disappears.
///
/// When the assertion is unavailable on a build, the clock is covered instead: an opaque panel on
/// its Accessibility bounds, which keeps the strip's width and needs Accessibility access.
@MainActor
@Observable
public final class SystemClockHider {
    /// How the clock is currently hidden.
    public enum State: Equatable, Sendable {
        case off
        case removed
        case covered
        case coverNeedsAccessibility
        case failed(String)
    }

    /// The one hider, shared by the coordinator and Time settings.
    public static let shared = SystemClockHider()

    public private(set) var state: State = .off

    @ObservationIgnored private let assertion = MenuBarAssessmentAssertion()
    @ObservationIgnored private let cover = SystemClockCover()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var isEnabled = false
    @ObservationIgnored private var coverColor: NSColor = .black
    @ObservationIgnored private var applyTask: Task<Void, Never>?
    private static let logger = Logger(subsystem: "com.barometer.app", category: "clock-hider")

    init() {}

    /// Applies the Time setting.
    public func apply(isEnabled: Bool, coverColor: NSColor) {
        self.coverColor = coverColor
        guard isEnabled else {
            if self.isEnabled { Self.logger.notice("clock hider off") }
            self.isEnabled = false
            applyTask?.cancel()
            stopWatchingApplications()
            assertion.invalidate()
            cover.apply(isEnabled: false, fallbackColor: coverColor)
            state = .off
            return
        }
        self.isEnabled = true
        startWatchingApplications()
        reapply()
    }

    /// Activates the assertion with the current allowlist, or falls back to the cover.
    private func reapply() {
        applyTask?.cancel()
        applyTask = Task { [weak self] in
            guard let self else { return }
            let bundles = Self.runningBundleIdentifiers()
            do {
                try await assertion.activate(
                    allowedSystemItems: MenuBarAssessmentAssertion.allowedSystemItems(removing: [.clock]),
                    allowedBundleIdentifiers: bundles
                )
                guard !Task.isCancelled, isEnabled else { return }
                cover.apply(isEnabled: false, fallbackColor: coverColor)
                state = .removed
            } catch {
                guard !Task.isCancelled, isEnabled else { return }
                Self.logger.warning("assertion unavailable, covering the clock instead")
                if !SystemClockCover.isTrusted {
                    SystemClockCover.requestAccess()
                }
                cover.apply(isEnabled: true, fallbackColor: coverColor)
                state = SystemClockCover.isTrusted ? .covered : .coverNeedsAccessibility
            }
        }
    }

    /// Bundle identifiers of every running application, so the assertion removes none of their items.
    static func runningBundleIdentifiers() -> [String] {
        Array(Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))).sorted()
    }

    private func startWatchingApplications() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        let names = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isEnabled, self.assertion.isActive else { return }
                    self.reapply()
                }
            })
        }
    }

    private func stopWatchingApplications() {
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
    }

    /// Refreshes the cover's Accessibility state, for Settings polling.
    public func refreshCoverAccess() {
        guard isEnabled, state == .coverNeedsAccessibility || state == .covered else { return }
        cover.apply(isEnabled: true, fallbackColor: coverColor)
        state = SystemClockCover.isTrusted ? .covered : .coverNeedsAccessibility
    }
}
