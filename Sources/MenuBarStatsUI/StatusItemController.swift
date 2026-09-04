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

    /// Visibility policy evaluated from the current application and module settings.
    public typealias IsEnabled = @MainActor (AppSettings, ModuleSettings) -> Bool

    private let module: ModuleID
    private let statusItem: NSStatusItem
    private let store: ModuleStore<Sample>
    private let settingsStore: SettingsStore
    private let renderContent: Render
    private let isEnabled: IsEnabled
    private let logger = Logger(subsystem: "com.barometer.app", category: "render")

    /// Creates and begins observing a status item controller.
    public init(
        module: ModuleID,
        statusItem: NSStatusItem,
        store: ModuleStore<Sample>,
        settingsStore: SettingsStore,
        isEnabled: @escaping IsEnabled = { _, moduleSettings in moduleSettings.isEnabled },
        render: @escaping Render
    ) {
        self.module = module
        self.statusItem = statusItem
        self.store = store
        self.settingsStore = settingsStore
        self.isEnabled = isEnabled
        renderContent = render
        observeChanges()
        update()
    }

    /// Renders the latest store and settings state immediately.
    public func update() {
        let appSettings = settingsStore.settings
        let moduleSettings = appSettings.modules[module] ?? ModuleSettings()
        let isHiddenInCombined = StatusItemRendering.isHiddenByCombined(module: module, settings: appSettings)
        guard isEnabled(appSettings, moduleSettings), !isHiddenInCombined else {
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
        let context = StatusItemRendering.context(
            button: button,
            appSettings: appSettings,
            moduleSettings: moduleSettings,
            appearance: appearance
        )
        let content = renderContent(store.latestSample, store.history.entries, moduleSettings, context)
        button.image = content.image
        // NSStatusItem.variableLength adds AppKit's standard 8-point image inset
        // on both sides. An explicit length makes the rendered canvas authoritative,
        // so the user-controlled spacing can reach zero while each module remains
        // a separate, movable status item.
        statusItem.length = StatusItemRendering.itemLength(for: content.image)
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

@MainActor
enum StatusItemRendering {
    static func isHiddenByCombined(module: ModuleID, settings: AppSettings) -> Bool {
        module != .combined
            && settings.modules[.combined]?.isEnabled == true
            && settings.combined.hidesIndividualMembers
            && settings.combined.members.contains(module)
    }

    static func itemLength(for image: NSImage) -> CGFloat {
        max(1, ceil(image.size.width))
    }

    static func context(
        button: NSStatusBarButton,
        appSettings: AppSettings,
        moduleSettings: ModuleSettings,
        appearance: MenuBarAppearance? = nil
    ) -> RenderContext {
        let resolvedAppearance = appearance ?? (
            button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
        )
        let scale = min(1.35, max(0.75, appSettings.menuBarScale))
        return RenderContext(
            thickness: NSStatusBar.system.thickness,
            appearance: resolvedAppearance,
            palette: MenuBarPalette(
                light: NSColor(hex: appSettings.lightColor(for: moduleSettings)) ?? .controlAccentColor,
                dark: NSColor(hex: appSettings.darkColor(for: moduleSettings)) ?? .controlAccentColor
            ),
            graphPalette: MenuBarPalette(
                light: NSColor(hex: appSettings.graphLightColor(for: moduleSettings)) ?? .controlAccentColor,
                dark: NSColor(hex: appSettings.graphDarkColor(for: moduleSettings)) ?? .controlAccentColor
            ),
            fillPalette: MenuBarPalette(
                light: NSColor(hex: appSettings.fillLightColor(for: moduleSettings)) ?? .controlAccentColor,
                dark: NSColor(hex: appSettings.fillDarkColor(for: moduleSettings)) ?? .controlAccentColor
            ),
            warningPalette: MenuBarPalette(
                light: NSColor(hex: appSettings.warningLightColor(for: moduleSettings)) ?? .systemOrange,
                dark: NSColor(hex: appSettings.warningDarkColor(for: moduleSettings)) ?? .systemOrange
            ),
            criticalPalette: MenuBarPalette(
                light: NSColor(hex: appSettings.criticalLightColor(for: moduleSettings)) ?? .systemRed,
                dark: NSColor(hex: appSettings.criticalDarkColor(for: moduleSettings)) ?? .systemRed
            ),
            fontSize: min(14, max(9, appSettings.fontSize)),
            isMonochrome: appSettings.isMonochrome,
            scale: scale,
            horizontalSpacing: min(12, max(0, appSettings.menuBarSpacing)),
            graphOpacity: appSettings.graphOpacity,
            fontWeight: appSettings.fontWeight,
            usesCompactLayout: appSettings.usesCompactLayout
        )
    }
}

extension NSColor {
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
