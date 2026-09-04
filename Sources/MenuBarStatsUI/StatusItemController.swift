import AppKit
import MenuBarStatsCore
import Observation
import OSLog

/// Image and spoken value produced for one status item update.
public struct StatusItemContent {
    /// Rendered menu bar image.
    public let image: NSImage

    /// Live reading exposed through AXValue only.
    public let accessibilityValue: String

    /// Creates rendered status item content.
    public init(image: NSImage, accessibilityValue: String) {
        self.image = image
        self.accessibilityValue = accessibilityValue
    }
}

/// Observes one module store and applies rendered images to its permanent status item.
@MainActor
public final class StatusItemController<Sample: Sendable> {
    /// Rendering closure specialized for a module's sample type.
    public typealias Render = @MainActor (
        Sample?,
        [HistoryEntry<Sample>],
        ModuleSettings,
        RenderContext
    ) -> StatusItemContent

    private let module: ModuleID
    private let statusItem: NSStatusItem
    private let store: ModuleStore<Sample>
    private let settingsStore: SettingsStore
    private let renderContent: Render
    private let logger = Logger(subsystem: "net.brustein.MenuBarStats", category: "render")

    /// Creates and begins observing a status item controller.
    public init(
        module: ModuleID,
        statusItem: NSStatusItem,
        store: ModuleStore<Sample>,
        settingsStore: SettingsStore,
        render: @escaping Render
    ) {
        self.module = module
        self.statusItem = statusItem
        self.store = store
        self.settingsStore = settingsStore
        renderContent = render
        observeChanges()
        update()
    }

    /// Renders the latest store and settings state immediately.
    public func update() {
        let moduleSettings = settingsStore.settings.modules[module] ?? ModuleSettings()
        statusItem.isVisible = moduleSettings.isEnabled
        guard moduleSettings.isEnabled, let button = statusItem.button else {
            return
        }

        let appearance: MenuBarAppearance = button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? .dark
            : .light
        let appSettings = settingsStore.settings
        let context = RenderContext(
            thickness: NSStatusBar.system.thickness,
            appearance: appearance,
            palette: MenuBarPalette(
                light: NSColor(hex: moduleSettings.lightColor) ?? .controlAccentColor,
                dark: NSColor(hex: moduleSettings.darkColor) ?? .controlAccentColor
            ),
            fontSize: appSettings.fontSize,
            isMonochrome: appSettings.isMonochrome
        )
        let content = renderContent(store.latestSample, store.history.entries, moduleSettings, context)
        button.image = content.image
        button.setAccessibilityValue(content.accessibilityValue)
        let message = "module=\(module.displayName) value=\(content.accessibilityValue)"
        logger.debug("\(message, privacy: .public)")
    }

    private func observeChanges() {
        withObservationTracking {
            _ = store.latestSample
            _ = store.revision
            _ = settingsStore.settings
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else {
                    return
                }
                self.update()
                self.observeChanges()
            }
        }
    }
}

private extension NSColor {
    convenience init?(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard value.count == 6, let integer = UInt64(value, radix: 16) else {
            return nil
        }
        self.init(
            red: CGFloat((integer >> 16) & 0xFF) / 255,
            green: CGFloat((integer >> 8) & 0xFF) / 255,
            blue: CGFloat(integer & 0xFF) / 255,
            alpha: 1
        )
    }
}
