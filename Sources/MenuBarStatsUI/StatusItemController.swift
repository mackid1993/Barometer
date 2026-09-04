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
    private let logger = Logger(subsystem: "com.barometer.app", category: "render")

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
        guard moduleSettings.isEnabled else {
            if statusItem.isVisible {
                statusItem.isVisible = false
            }
            return
        }
        guard let button = statusItem.button else {
            return
        }

        let appearance: MenuBarAppearance = button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? .dark
            : .light
        let appSettings = settingsStore.settings
        let scale = min(1.35, max(0.75, appSettings.menuBarScale))
        let context = RenderContext(
            thickness: NSStatusBar.system.thickness,
            appearance: appearance,
            palette: MenuBarPalette(
                light: NSColor(hex: moduleSettings.lightColor) ?? .controlAccentColor,
                dark: NSColor(hex: moduleSettings.darkColor) ?? .controlAccentColor
            ),
            fontSize: min(14, appSettings.fontSize * scale),
            isMonochrome: appSettings.isMonochrome,
            scale: scale,
            horizontalSpacing: min(12, max(0, appSettings.menuBarSpacing))
        )
        let content = renderContent(store.latestSample, store.history.entries, moduleSettings, context)
        button.image = content.image
        button.setAccessibilityValue(content.accessibilityValue)
        if !statusItem.isVisible {
            statusItem.isVisible = true
        }
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
