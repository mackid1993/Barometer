import AppKit
import OSLog

/// Converts volume mount, unmount, and rename notifications into a main-actor callback.
@MainActor
public final class VolumeMountWatcher: NSObject {
    private let logger = Logger(subsystem: "com.barometer.app", category: "disks")

    /// Called whenever the mounted-volume list may have changed.
    public var onChange: (@MainActor () -> Void)?

    /// Starts observing workspace volume notifications.
    public override init() {
        super.init()
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(volumesDidChange),
            name: NSWorkspace.didMountNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(volumesDidChange),
            name: NSWorkspace.didUnmountNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(volumesDidChange),
            name: NSWorkspace.didRenameVolumeNotification,
            object: nil
        )
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func volumesDidChange() {
        logger.info("Mounted-volume list changed")
        onChange?()
    }
}
