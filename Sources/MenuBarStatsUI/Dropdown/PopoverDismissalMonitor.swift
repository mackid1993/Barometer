import AppKit

/// Watches clicks only while a popover is open, including clicks delivered to another application.
@MainActor
final class PopoverDismissalMonitor {
    private var hoverTimer: Timer?
    private var lastInsideTime: TimeInterval = 0
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var containsPoint: (@MainActor (NSPoint) -> Bool)?
    private var dismiss: (@MainActor () -> Void)?

    func start(containsPoint: @escaping @MainActor (NSPoint) -> Bool,
               tracksHover: Bool = true, dismiss: @escaping @MainActor () -> Void) {
        stop()
        self.containsPoint = containsPoint
        self.dismiss = dismiss
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
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated {
                let point = event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
                self?.handleClick(at: point)
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleClick(at: NSEvent.mouseLocation) }
        }
    }

    func handleClick(at point: NSPoint) {
        guard let containsPoint, !containsPoint(point) else { return }
        let action = dismiss
        stop()
        action?()
    }

    func handleHover(at point: NSPoint, time: TimeInterval) {
        guard let containsPoint else { return }
        if containsPoint(point) {
            lastInsideTime = time
        } else if time - lastInsideTime >= 0.3 {
            handleClick(at: point)
        }
    }

    func stop() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        containsPoint = nil
        dismiss = nil
    }
}
