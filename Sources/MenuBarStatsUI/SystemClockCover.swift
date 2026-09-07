//
//  SystemClockCover.swift
//  Barometer
//
//  Derived from SystemClockCover.swift in Thaw (https://github.com/thaw-app/Thaw),
//  Copyright © 2026 Toni Förster, licensed under the GNU GPLv3, and used with the
//  permission of Thaw's maintainers. Barometer is licensed under the GNU GPLv3.
//

import AppKit
import ApplicationServices
import OSLog

/// Hides the macOS clock, and nothing else, by covering it.
///
/// Nothing on macOS 27 removes the clock without taking other things with it, and the clock has no
/// Control Center preference to turn off, so it is covered rather than removed: an opaque panel
/// above the menu bar sits exactly on the clock's Accessibility bounds and absorbs clicks so the
/// covered clock cannot open Notification Center. The trade-off is explicit: the clock's width is
/// not reclaimed. Locating the clock reads MenuBarAgent's Accessibility tree, which needs
/// Accessibility access for Barometer; the cover simply stays off until that is allowed.
///
/// The cover follows the clock: its width changes on every minute, and its origin changes whenever
/// something to its left appears or leaves, so the bounds are re-read once a second and on screen
/// and Space changes. The fill is the color chosen in Time settings, whose picker has an eyedropper
/// for lifting the bar's own color; Thaw samples the bar instead, which needs Screen Recording.
@MainActor
public final class SystemClockCover {
    /// Accessibility identifier of the system clock item.
    static let clockIdentifier = "com.apple.menuextra.clock"

    /// Processes that host the system menu extras, most recent macOS first.
    static let hostBundleIdentifiers = ["com.apple.MenuBarAgent", "com.apple.controlcenter"]

    private static let logger = Logger(subsystem: "com.barometer.app", category: "clock-cover")

    private var panels: [CGDirectDisplayID: NSPanel] = [:]
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var isEnabled = false
    private var fallbackColor: NSColor = .black

    public init() {}

    deinit {
        // Panels and observers are released with the object; teardown ran when the setting went off.
    }

    // MARK: - Access

    /// Whether macOS currently lists Barometer as an allowed Accessibility client.
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Asks macOS to list Barometer under Accessibility, showing the system prompt when it is not yet allowed.
    /// Call this only from a direct user action, such as turning the setting on.
    @discardableResult
    public static func requestAccess() -> Bool {
        // The header exports the option key as a global `var`, which strict concurrency rejects;
        // its value is the documented string "AXTrustedCheckOptionPrompt".
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Opens the Accessibility pane of System Settings.
    public static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Control

    /// Turns the cover on or off and sets the fill.
    public func apply(isEnabled: Bool, fallbackColor: NSColor) {
        self.fallbackColor = fallbackColor
        guard isEnabled else {
            if self.isEnabled { Self.logger.notice("clock cover off") }
            self.isEnabled = false
            stopWatching()
            teardownAll()
            return
        }
        if !self.isEnabled { Self.logger.notice("clock cover on") }
        self.isEnabled = true
        startWatching()
        update()
    }

    private func startWatching() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.update() } })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.update() } })
    }

    private func stopWatching() {
        timer?.invalidate()
        timer = nil
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
    }

    // MARK: - Reconciliation

    /// Reconciles the cover panels against the clock's current bounds.
    func update() {
        guard isEnabled, Self.isTrusted else {
            teardownAll()
            return
        }
        var covered = Set<CGDirectDisplayID>()
        for bounds in Self.clockBounds() {
            guard let displayID = Self.displayID(for: bounds),
                  Self.boundsAreInMenuBarBand(bounds, of: displayID),
                  let coverRect = Self.cocoaRect(from: bounds)
            else { continue }
            present(displayID: displayID, coverRect: coverRect)
            covered.insert(displayID)
        }
        for displayID in panels.keys where !covered.contains(displayID) {
            teardown(displayID)
        }
    }

    /// Every system clock item's bounds, in top-left global coordinates.
    static func clockBounds() -> [CGRect] {
        var results: [CGRect] = []
        for bundleIdentifier in hostBundleIdentifiers {
            for host in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier) {
                let application = AXUIElementCreateApplication(host.processIdentifier)
                guard let extras = elementAttribute(kAXExtrasMenuBarAttribute, of: application) else { continue }
                for clock in elements(withIdentifier: clockIdentifier, under: extras, depth: 0) {
                    if let bounds = frame(of: clock), !bounds.isEmpty { results.append(bounds) }
                }
            }
            if !results.isEmpty { break }
        }
        return results
    }

    /// The display whose bounds contain the rect's center.
    static func displayID(for bounds: CGRect) -> CGDirectDisplayID? {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        return NSScreen.screens.first { CGDisplayBounds($0.displayID).contains(center) }?.displayID
    }

    /// Whether the bounds still name a strip of live menu bar on the display.
    ///
    /// Item bounds are a snapshot: a clock enumerated before a display change can name a strip that
    /// is no longer menu bar, and behind a fullscreen app the bar is not drawn while the item keeps
    /// its last bounds. The band is tested at the center so a point of overhang does not uncover the
    /// clock, and the generous height ceiling rejects a rect that drifted off the bar.
    static func boundsAreInMenuBarBand(_ bounds: CGRect, of displayID: CGDirectDisplayID) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else { return false }
        let displayBounds = CGDisplayBounds(displayID)
        let barHeight = Self.menuBarHeight(of: screen)
        guard barHeight > 0 else { return false }
        return boundsAreInBand(bounds, displayBounds: displayBounds, barHeight: barHeight)
    }

    /// Pure form of the band test, for tests.
    static func boundsAreInBand(_ bounds: CGRect, displayBounds: CGRect, barHeight: CGFloat) -> Bool {
        let band = CGRect(x: displayBounds.minX, y: displayBounds.minY, width: displayBounds.width, height: barHeight)
        return band.contains(CGPoint(x: bounds.midX, y: bounds.midY)) && bounds.height <= barHeight * 2
    }

    /// Height of the menu bar on a screen, zero when the bar is hidden (a fullscreen Space).
    static func menuBarHeight(of screen: NSScreen) -> CGFloat {
        let height = screen.frame.maxY - screen.visibleFrame.maxY
        return max(0, height)
    }

    /// Converts a top-left global rect to a bottom-left Cocoa rect. Both share the primary display's
    /// left origin and differ only by a vertical flip about the primary's height.
    static func cocoaRect(from cgRect: CGRect, primaryHeight: CGFloat? = NSScreen.screens.first?.frame.maxY) -> CGRect? {
        guard let primaryHeight else { return nil }
        return CGRect(x: cgRect.origin.x, y: primaryHeight - cgRect.maxY, width: cgRect.width, height: cgRect.height)
    }

    // MARK: - Panels

    private func present(displayID: CGDirectDisplayID, coverRect: CGRect) {
        let isNew = panels[displayID] == nil
        let panel = panels[displayID] ?? Self.makePanel()
        panels[displayID] = panel
        panel.setFrame(coverRect, display: true)
        panel.backgroundColor = fallbackColor
        if !panel.isVisible { panel.orderFrontRegardless() }
        if isNew { Self.logger.notice("clock covered on display \(displayID) at \(NSStringFromRect(coverRect), privacy: .public)") }
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.animationBehavior = .none
        panel.isOpaque = true
        panel.hasShadow = false
        // Above the menu bar's own level (24).
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        panel.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .canJoinAllSpaces, .stationary]
        panel.hidesOnDeactivate = false
        panel.canHide = false
        // Absorbs clicks so a covered clock cannot open Notification Center; nonactivating so
        // absorbing one never steals focus.
        panel.ignoresMouseEvents = false
        panel.sharingType = .none
        panel.contentView = NSView()
        return panel
    }

    private func teardown(_ displayID: CGDirectDisplayID) {
        guard let panel = panels.removeValue(forKey: displayID) else { return }
        panel.orderOut(nil)
        Self.logger.notice("clock cover removed on display \(displayID)")
    }

    private func teardownAll() {
        guard !panels.isEmpty else { return }
        for panel in panels.values { panel.orderOut(nil) }
        panels.removeAll()
    }

    // MARK: - Accessibility helpers

    private static func elements(withIdentifier identifier: String, under root: AXUIElement, depth: Int) -> [AXUIElement] {
        if valueAttribute(kAXIdentifierAttribute, of: root) as? String == identifier { return [root] }
        guard depth < 4, let children = valueAttribute(kAXChildrenAttribute, of: root) as? [AXUIElement] else { return [] }
        return children.flatMap { elements(withIdentifier: identifier, under: $0, depth: depth + 1) }
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = valueAttribute(kAXPositionAttribute, of: element),
              let sizeValue = valueAttribute(kAXSizeAttribute, of: element),
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(unsafeDowncast(positionValue, to: AXValue.self), .cgPoint, &position)
        AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size)
        return CGRect(origin: position, size: size)
    }

    private static func elementAttribute(_ name: String, of element: AXUIElement) -> AXUIElement? {
        guard let value = valueAttribute(name, of: element), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func valueAttribute(_ name: String, of element: AXUIElement) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}

extension NSScreen {
    /// The Core Graphics display identifier behind this screen.
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
