import AppKit

/// Watches pointer exit only while a dropdown is open.
///
/// Native menus own outside-click dismissal. Attached panels use this pointer-exit timer because a
/// global click monitor competes with the event taps used by menu bar managers.
@MainActor
final class PopoverDismissalMonitor {
    static let hoverExitDelay: TimeInterval = 1.0
    static let managerHandoffDelay: TimeInterval = 2.0

    private var hoverTimer: Timer?
    private var hasEntered = false
    private var startedAt: TimeInterval = 0
    private var lastInsideTime: TimeInterval = 0
    private var containsPoint: (@MainActor (NSPoint) -> Bool)?
    private var dismiss: (@MainActor () -> Void)?

    func start(containsPoint: @escaping @MainActor (NSPoint) -> Bool,
               tracksHover: Bool = true, dismiss: @escaping @MainActor () -> Void) {
        stop()
        self.containsPoint = containsPoint
        self.dismiss = dismiss
        hasEntered = false
        startedAt = ProcessInfo.processInfo.systemUptime
        lastInsideTime = startedAt
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleHover(at: NSEvent.mouseLocation, time: ProcessInfo.processInfo.systemUptime)
            }
        }
        if tracksHover {
            RunLoop.main.add(timer, forMode: .common)
            hoverTimer = timer
        }
    }

    func handleClick(at point: NSPoint) {
        guard let containsPoint, !containsPoint(point) else { return }
        dismissOutside()
    }

    func handleHover(at point: NSPoint, time: TimeInterval) {
        guard let containsPoint else { return }
        if containsPoint(point) {
            hasEntered = true
            lastInsideTime = time
        } else if hasEntered, time - lastInsideTime >= Self.hoverExitDelay {
            dismissOutside()
        } else if !hasEntered, time - startedAt >= Self.managerHandoffDelay {
            // A manager can synthesize the press away from the real status-item frame. If AppKit
            // never exposes a window under that pointer, do not leave an invisible menu tracking.
            dismissOutside()
        }
    }

    private func dismissOutside() {
        let action = dismiss
        stop()
        action?()
    }

    func stop() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        startedAt = 0
        lastInsideTime = 0
        hasEntered = false
        containsPoint = nil
        dismiss = nil
    }
}
