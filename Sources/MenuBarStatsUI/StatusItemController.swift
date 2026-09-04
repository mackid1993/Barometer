import AppKit
import MenuBarStatsCore
import OSLog
import Observation

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
    public typealias Render =
        @MainActor (
            Sample?,
            [HistoryEntry<Sample>],
            ModuleSettings,
            RenderContext
        ) -> StatusItemContent

    /// Visibility policy evaluated from the current application and module settings.
    public typealias IsEnabled = @MainActor (AppSettings, ModuleSettings) -> Bool

    private let module: ModuleID
    private let statusItem: NSStatusItem?
    private let store: ModuleStore<Sample>
    private let settingsStore: SettingsStore
    private let renderContent: Render
    private let isEnabled: IsEnabled
    private let accessibilityLabel: String
    private let logger = Logger(subsystem: "com.barometer.app", category: "render")
    private var lengthLatch = StatusItemLengthLatch()
    private var geometryLatch = StatusItemGeometryLatch()

    /// Creates and begins observing a status item controller.
    public init(
        module: ModuleID,
        statusItem: NSStatusItem?,
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
        accessibilityLabel = statusItem?.button?.accessibilityLabel() ?? module.displayName
        renderContent = render
        observeChanges()
        update()
    }

    /// Renders the latest store and settings state immediately.
    public func update() {
        let appSettings = settingsStore.settings
        let moduleSettings = appSettings.modules[module] ?? ModuleSettings()
        let geometry = geometryLatch.resolve(
            StatusItemGeometry(
                fontSize: settingsStore.launchMenuBarFontSize,
                scale: settingsStore.launchMenuBarScale,
                fontWeight: settingsStore.launchMenuBarFontWeight
            )
        )
        let isHiddenInCombined = StatusItemRendering.isHiddenByCombined(module: module, settings: appSettings)
        guard isEnabled(appSettings, moduleSettings), !isHiddenInCombined else {
            if let statusItem, statusItem.isVisible {
                statusItem.isVisible = false
            }
            return
        }
        guard let statusItem, let button = statusItem.button else {
            return
        }

        let appearance: MenuBarAppearance =
            button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? .dark
            : .light
        let context = StatusItemRendering.context(
            button: button,
            appSettings: appSettings,
            moduleSettings: moduleSettings,
            appearance: appearance,
            geometry: geometry
        )
        let content = renderContent(store.latestSample, store.history.entries, moduleSettings, context)
        // Menu bar managers on macOS 27 can move an item when its AppKit length changes.
        // Once this controller has applied a length, both its outer frame and its
        // geometry are immutable for the rest of the process lifetime. A normal launch
        // recomputes both from the complete saved widget set.
        let naturalLength = StatusItemRendering.itemLength(for: content.image)
        let proposedLength = StatusItemRendering.roundedLength(naturalLength)
        let lengthDecision = lengthLatch.resolve(proposedLength)
        let displayedImage = StatusItemRendering.image(content.image, framedTo: lengthDecision.length)
        // AppKit derives the button's AX label from its replacement image. Reapply the
        // permanent child label on every render so dynamic images never collapse distinct
        // Barometer widgets into one accessibility identity.
        displayedImage.accessibilityDescription = accessibilityLabel
        button.image = displayedImage
        // CONTRACT: This is the sole production writer of statusItem.length. It may run
        // once per controller lifetime, before the item is made visible. See
        // docs/MACOS27_STATUS_ITEM_SIZING.md before changing this branch.
        // NSStatusItem.variableLength adds AppKit's standard 8-point image inset
        // on both sides. An explicit length makes the zero-padding rendered canvas
        // authoritative while each module remains a separate, movable status item.
        if lengthDecision.shouldAssign {
            statusItem.length = lengthDecision.length
        }
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

/// Launch-time dimensions shared by every rendering from one status-item controller.
struct StatusItemGeometry: Equatable {
    let fontSize: CGFloat
    let scale: CGFloat
    let fontWeight: MenuBarFontWeight
}

/// Prevents a settings update from shrinking content inside an immutable AppKit frame.
struct StatusItemGeometryLatch {
    private(set) var geometry: StatusItemGeometry?

    mutating func resolve(_ proposed: StatusItemGeometry) -> StatusItemGeometry {
        if let geometry {
            return geometry
        }
        geometry = proposed
        return proposed
    }
}

/// One-way guard around the live AppKit width. Once resolved, later proposals cannot
/// replace the width used by this process; the next launch calculates a fresh width.
struct StatusItemLengthLatch {
    private(set) var length: CGFloat?

    mutating func resolve(_ proposed: CGFloat) -> (length: CGFloat, shouldAssign: Bool) {
        if let length {
            return (length, false)
        }
        length = proposed
        return (proposed, true)
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

    /// Item lengths use a narrow grid that absorbs fractional pixels without wasting notch space.
    static let widthStep: CGFloat = 2

    static func roundedLength(_ natural: CGFloat) -> CGFloat {
        max(widthStep, (natural / widthStep).rounded(.up) * widthStep)
    }

    static func geometry(appSettings: AppSettings) -> StatusItemGeometry {
        StatusItemGeometry(
            fontSize: appSettings.effectiveMenuBarFontSize,
            scale: appSettings.effectiveMenuBarScale,
            fontWeight: appSettings.fontWeight
        )
    }

    /// Frames a rendering in a canvas of exactly `length` points. Content stays at full size
    /// on the leading edge, so layout changes never recenter or miniaturize live typography.
    /// Content wider than the fixed frame is clipped until the next normal launch.
    static func image(_ image: NSImage, framedTo length: CGFloat) -> NSImage {
        guard abs(length - image.size.width) > 0.01 else {
            return image
        }
        let height = image.size.height
        let fitted = NSImage(size: NSSize(width: length, height: height), flipped: false) { rect in
            let origin = NSPoint(
                x: 0,
                y: floor((rect.height - image.size.height) / 2)
            )
            image.draw(in: NSRect(origin: origin, size: image.size))
            return true
        }
        fitted.isTemplate = image.isTemplate
        return fitted
    }

    static func context(
        button: NSStatusBarButton,
        appSettings: AppSettings,
        moduleSettings: ModuleSettings,
        appearance: MenuBarAppearance? = nil,
        geometry: StatusItemGeometry? = nil
    ) -> RenderContext {
        let resolvedAppearance =
            appearance
            ?? (button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light)
        let geometry = geometry ?? self.geometry(appSettings: appSettings)
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
            fontSize: geometry.fontSize,
            isMonochrome: appSettings.isMonochrome,
            scale: geometry.scale,
            graphOpacity: appSettings.graphOpacity,
            fontWeight: geometry.fontWeight
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
