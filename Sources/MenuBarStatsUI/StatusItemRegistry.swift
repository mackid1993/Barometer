import AppKit
import MenuBarStatsCore
import OSLog

/// Owns every status item for the lifetime of the application process.
@MainActor
public final class StatusItemRegistry: NSObject {
    private static let identityLogger = Logger(subsystem: "com.barometer.app", category: "identity")

    private let settingsAction: @MainActor () -> Void
    private let quitAction: @MainActor () -> Void
    private var items: [ModuleID: NSStatusItem] = [:]

    /// Creates all permanent module status items.
    public init(
        settingsAction: @escaping @MainActor () -> Void,
        quitAction: @escaping @MainActor () -> Void
    ) {
        self.settingsAction = settingsAction
        self.quitAction = quitAction
        super.init()

        for module in ModuleID.allCases {
            let statusItem = makeItem(for: module)
            items[module] = statusItem
        }

        configureCPUItem()
        perform(#selector(runIdentitySelfTest), with: nil, afterDelay: 1)
    }

    /// Returns the permanent status item for a module.
    public func item(for module: ModuleID) -> NSStatusItem {
        guard let statusItem = items[module] else {
            preconditionFailure("Missing status item for \(module.displayName)")
        }
        return statusItem
    }

    /// Changes a status item's visibility without changing its identity or lifetime.
    public func setVisible(_ isVisible: Bool, for module: ModuleID) {
        item(for: module).isVisible = isVisible
    }

    private func makeItem(for module: ModuleID) -> NSStatusItem {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = module.autosaveName
        statusItem.behavior = []
        statusItem.isVisible = module == .cpu

        guard let button = statusItem.button else {
            preconditionFailure("AppKit did not create a status item button for \(module.displayName)")
        }
        button.title = ""
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.setAccessibilityIdentifier(module.autosaveName)
        button.setAccessibilityLabel(module.displayName)
        return statusItem
    }

    private func configureCPUItem() {
        let statusItem = item(for: .cpu)
        statusItem.button?.image = Self.makeTextImage("CPU")

        let menu = NSMenu()
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Barometer",
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    private static func makeTextImage(_ text: String) -> NSImage {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.black,
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedText.size()
        let height = NSStatusBar.system.thickness
        let image = NSImage(size: NSSize(width: ceil(textSize.width) + 4, height: height), flipped: false) { rect in
            let origin = NSPoint(
                x: 2,
                y: floor((rect.height - textSize.height) / 2)
            )
            attributedText.draw(at: origin)
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func openSettings() {
        settingsAction()
    }

    @objc private func quitApplication() {
        quitAction()
    }

    @objc private func runIdentitySelfTest() {
        for module in ModuleID.allCases {
            let statusItem = item(for: module)
            guard let button = statusItem.button else {
                assertionFailure("Missing status item button for \(module.displayName)")
                continue
            }

            let windowTitle = button.window?.title ?? ""
            let identifier = button.accessibilityIdentifier()
            let label = button.accessibilityLabel() ?? ""
            let title = button.accessibilityTitle() ?? ""
            let message = "autosaveName=\(module.autosaveName) window.title=\(windowTitle) "
                + "AXIdentifier=\(identifier) AXLabel=\(label) AXTitle=\(title)"
            Self.identityLogger.debug("\(message, privacy: .public)")

            assert(windowTitle == module.autosaveName)
            assert(identifier == module.autosaveName)
            assert(label == module.displayName)
            assert(title.isEmpty)
            assert(button.title.isEmpty)
        }
    }
}
