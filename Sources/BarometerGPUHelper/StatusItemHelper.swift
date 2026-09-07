import AppKit
import OSLog

/// Publishes a single status item under this helper's own bundle identifier.
///
/// A menu bar manager's concealment allowlist on macOS 27 is keyed by the bundle
/// identifier of the process that published the item, so every item an application wants
/// hidden independently of its siblings has to come from a separate bundle. This helper is
/// the prototype for that split: it mirrors the main app's identity contract exactly, but
/// owns `com.barometer.gpu` instead of `com.barometer.app`.
@MainActor
final class StatusItemHelper: NSObject, NSApplicationDelegate {
    // MARK: - Identity

    /// The only bundle identifier permitted to create this helper's status item.
    static let bundleIdentifier = "com.barometer.gpu"

    /// Permanent AppKit autosave name. Matches the main app's table entry for the module,
    /// which is safe because the position-table key is scoped by bundle identifier:
    /// `status:com.barometer.gpu::Barometer.GPU` cannot collide with the app's own
    /// `status:com.barometer.app::Barometer.GPU`.
    static let autosaveName = "Barometer.GPU"

    /// Permanent human-readable accessibility label.
    static let displayName = "GPU"

    private static let logger = Logger(subsystem: bundleIdentifier, category: "identity")

    private var statusItem: NSStatusItem?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_: Notification) {
        // Contract rule 2, applied per bundle: validate bundle identity before touching
        // NSStatusBar. An unbundled invocation has no application identity on macOS 27 and
        // would pollute a manager's discovery state.
        guard Bundle.main.bundleIdentifier == Self.bundleIdentifier else {
            Self.logger.error("Refusing to create a status item outside \(Self.bundleIdentifier, privacy: .public)")
            NSApplication.shared.terminate(nil)
            return
        }

        statusItem = makeItem()
        logIdentity()
    }

    // MARK: - Status item

    private func makeItem() -> NSStatusItem {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Attach the stable identity before the first visibility transition, so a manager
        // never observes an unnamed placeholder and pairs the wrong autosave name with it.
        statusItem.autosaveName = Self.autosaveName
        statusItem.behavior = []

        guard let button = statusItem.button else {
            preconditionFailure("AppKit did not create a status item button for \(Self.displayName)")
        }
        button.title = ""
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.image = Self.markerImage()
        button.setAccessibilityIdentifier(Self.autosaveName)
        button.setAccessibilityLabel(Self.displayName)
        statusItem.isVisible = true
        return statusItem
    }

    /// A deliberately distinct glyph. The prototype runs alongside the real Barometer GPU
    /// item, so the two have to be tellable apart at a glance in the menu bar.
    private static func markerImage() -> NSImage? {
        let image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: displayName)
        image?.isTemplate = true
        return image
    }

    // MARK: - Diagnostics

    /// Records what a menu bar manager will read, so the run can be checked against the
    /// system's `TrailingItemPreferredPositions` table without attaching a debugger.
    private func logIdentity() {
        guard let button = statusItem?.button else {
            return
        }
        let message =
            "bundle=\(Bundle.main.bundleIdentifier ?? "(none)") "
            + "autosaveName=\(statusItem?.autosaveName ?? "") "
            + "window.title=\(button.window?.title ?? "") "
            + "AXIdentifier=\(button.accessibilityIdentifier()) "
            + "AXLabel=\(button.accessibilityLabel() ?? "") "
            + "frame=\(NSStringFromRect(button.window?.frame ?? .zero))"
        Self.logger.notice("\(message, privacy: .public)")
    }
}
