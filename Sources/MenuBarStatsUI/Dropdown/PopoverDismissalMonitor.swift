import AppKit

/// Watches pointer exit only while a dropdown is open.
///
/// Native menus own outside-click dismissal. Attached panels use this pointer-exit timer because a
/// global click monitor competes with the event taps used by menu bar managers.
@MainActor
final class PopoverDismissalMonitor {
    static let hoverExitDelay: TimeInterval = 0.8

    private var hoverTimer: Timer?
    private var hasEntered = false
    private var lastInsideTime: TimeInterval = 0
    private var containsPoint: (@MainActor (NSPoint) -> Bool)?
    private var dismiss: (@MainActor () -> Void)?

    func start(containsPoint: @escaping @MainActor (NSPoint) -> Bool,
               tracksHover: Bool = true, dismiss: @escaping @MainActor () -> Void) {
        stop()
        self.containsPoint = containsPoint
        self.dismiss = dismiss
        hasEntered = false
        lastInsideTime = ProcessInfo.processInfo.systemUptime
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
        containsPoint = nil
        dismiss = nil
    }
}
