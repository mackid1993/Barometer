import AppKit

/// Converts workspace display sleep and wake notifications into main-actor callbacks.
@MainActor
public final class DisplaySleepWatcher: NSObject {
    /// Called when the displays go to sleep.
    public var onSleep: (@MainActor () -> Void)?

    /// Called when the displays wake.
    public var onWake: (@MainActor () -> Void)?

    /// Starts observing workspace notifications.
    public override init() {
        super.init()
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(displayDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(displayDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func displayDidSleep() {
        onSleep?()
    }

    @objc private func displayDidWake() {
        onWake?()
    }
}
