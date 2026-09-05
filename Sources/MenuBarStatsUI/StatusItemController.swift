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
public final class StatusItemController<Sample: HistoryProjecting> {
    /// Rendering closure specialized for a module's sample type.
    public typealias Render =
        @MainActor (
            Sample?,
            [HistoryEntry<Sample.GraphValue>],
            ModuleSettings,
            RenderContext
        ) -> StatusItemContent

    /// Visibility policy evaluated from the current application and module settings.
    public typealias IsEnabled = @MainActor (AppSettings, ModuleSettings) -> Bool

    private let module: ModuleID
    private var statusItem: NSStatusItem?
    private let store: ModuleStore<Sample>
    private let settingsStore: SettingsStore
    private let renderContent: Render
    private let isEnabled: IsEnabled
    private var accessibilityLabel: String
    private var visibilityLatch = StatusItemVisibilityLatch()
    private let logger = Logger(subsystem: "com.barometer.app", category: "render")
    private var lengthLatch = StatusItemLengthLatch()
    private var appliedImageFingerprint: Int?
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

    /// Attaches a newly enabled permanent item without replacing an existing item.
    public func attach(statusItem: NSStatusItem) {
        guard self.statusItem == nil else {
            return
        }
        self.statusItem = statusItem
        accessibilityLabel = statusItem.button?.accessibilityLabel() ?? module.displayName
        update()
    }

    /// Allows the fully configured item to follow its settings visibility.
    public func activateVisibility() {
        guard visibilityLatch.activate() else {
            return
        }
        update()
    }

    /// Renders the latest store and settings state immediately.
    public func update() {
        let appSettings = settingsStore.settings
        let moduleSettings = appSettings.modules[module] ?? ModuleSettings()
        let geometry = geometryLatch.resolve(
            StatusItemGeometry(
                fontSize: settingsStore.launchMenuBarFontSize,
                scale: settingsStore.launchMenuBarScale
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
        // Renderers get the newest samples rather than the whole buffer, which meant every update
        // allocated and copied one entry per retained sample and grew with uptime.
        //
        // This does change the graph modes: `GraphRenderer` plots every value it is given across
        // about forty points of width, so CPU and Memory graphs previously smeared an entire day of
        // samples into that space. They now show the most recent window instead, which is the
        // readable interpretation and the one the other modules already used via `suffix`.
        let history = store.history.recent(StatusItemRendering.renderedHistoryLimit)
        let content = renderContent(store.latestSample, history, moduleSettings, context)
        let reservedFontWeightWidth: CGFloat
        if lengthLatch.length == nil, appSettings.fontWeight != .semibold {
            var sizingSettings = appSettings
            sizingSettings.fontWeight = .semibold
            let sizingContext = StatusItemRendering.context(
                button: button,
                appSettings: sizingSettings,
                moduleSettings: moduleSettings,
                appearance: appearance,
                geometry: geometry
            )
            reservedFontWeightWidth = renderContent(
                store.latestSample,
                history,
                moduleSettings,
                sizingContext
            ).image.size.width
        } else {
            reservedFontWeightWidth = content.image.size.width
        }
        // Menu bar managers on macOS 27 can move an item when its AppKit length changes.
        // Once this controller has applied a length, both its outer frame and its
        // geometry are immutable for the rest of the process lifetime. A normal launch
        // recomputes both from the complete saved widget set.
        let naturalLength = max(StatusItemRendering.itemLength(for: content.image), reservedFontWeightWidth)
        let proposedLength = StatusItemRendering.roundedLength(naturalLength)
        let lengthDecision = lengthLatch.resolve(proposedLength)
        let displayedImage = StatusItemRendering.image(content.image, framedTo: lengthDecision.length)
        // AppKit derives the button's AX label from its replacement image. Reapply the
        // permanent child label on every render so dynamic images never collapse distinct
        // Barometer widgets into one accessibility identity.
        displayedImage.accessibilityDescription = accessibilityLabel
        // Replacing the image makes AppKit redraw the item, so an unchanged image is skipped. The
        // fingerprint is the drawn pixels, not the reading, so graphs that move while their value
        // reads the same still update.
        let fingerprint = displayedImage.tiffRepresentation?.hashValue
        if fingerprint == nil || fingerprint != appliedImageFingerprint {
            button.image = displayedImage
            appliedImageFingerprint = fingerprint
        }
        // CONTRACT: This is the sole production writer of statusItem.length. It may run
        // once per controller lifetime, before the item is made visible. See
        // docs/MACOS27_STATUS_ITEM_SIZING.md before changing this branch.
        // NSStatusItem.variableLength adds AppKit's standard 8-point image inset
        // on both sides. An explicit length makes the zero-padding rendered canvas
        // authoritative while each module remains a separate, movable status item.
        if lengthDecision.shouldAssign {
            statusItem.length = lengthDecision.length
        }
        if button.accessibilityValue() as? String != content.accessibilityValue {
            button.setAccessibilityValue(content.accessibilityValue)
        }
        if visibilityLatch.isActivated, !statusItem.isVisible {
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

/// Prevents a controller from publishing its AX child before the coordinator has
/// finished configuring the complete launch set.
struct StatusItemVisibilityLatch {
    private(set) var isActivated = false

    mutating func activate() -> Bool {
        guard !isActivated else {
            return false
        }
        isActivated = true
        return true
    }
}

@MainActor
enum StatusItemRendering {
    /// Newest samples handed to a renderer.
    ///
    /// The widest menu bar graph is well under this, so it bounds the per-update cost without
    /// changing any drawn output.
    static let renderedHistoryLimit = 240

    /// Whether an enabled stack replaces this module's individual item.
    static func isHiddenByCombined(module: ModuleID, settings: AppSettings) -> Bool {
        module != .combined && settings.hiddenBySourceStacks.contains(module)
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
            scale: appSettings.effectiveMenuBarScale
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
            backingScaleFactor: button.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2,
            graphOpacity: appSettings.graphOpacity,
            fontWeight: appSettings.fontWeight
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
