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
    private let statusItem: NSStatusItem
    private let store: ModuleStore<Sample>
    private let settingsStore: SettingsStore
    private let renderContent: Render
    private let isEnabled: IsEnabled
    private let logger = Logger(subsystem: "com.barometer.app", category: "render")
    private var appliedLength: CGFloat?
    private var appliedGeometry: StatusItemGeometry?
    private var lengthSettings: AppSettings?

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
        // Controllers are created once per permanent status item and live for the whole
        // process, so the observation is never removed.
        NotificationCenter.default.addObserver(
            forName: .barometerStageItemWidths,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.update()
            }
        }
        update()
    }

    /// Renders the latest store and settings state immediately.
    public func update() {
        let appSettings = settingsStore.settings
        let moduleSettings = appSettings.modules[module] ?? ModuleSettings()
        let isHiddenInCombined = StatusItemRendering.isHiddenByCombined(module: module, settings: appSettings)
        guard isEnabled(appSettings, moduleSettings), !isHiddenInCombined else {
            // Remember the geometry settings seen while hidden. If this item is enabled
            // later, the settings delta makes its safe first render use current geometry
            // instead of a stale committed width.
            lengthSettings = appSettings
            if statusItem.isVisible {
                statusItem.isVisible = false
            }
            StatusItemRendering.clearInactiveVisibilityPreferences(autosaveName: statusItem.autosaveName)
            return
        }
        guard let button = statusItem.button else {
            return
        }

        let appearance: MenuBarAppearance =
            button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? .dark
            : .light
        let currentGeometry = StatusItemGeometry(settings: appSettings)
        let activeGeometry = appliedGeometry ?? currentGeometry
        let context = StatusItemRendering.context(
            button: button,
            appSettings: appSettings,
            moduleSettings: moduleSettings,
            appearance: appearance,
            geometry: activeGeometry
        )
        let content = renderContent(store.latestSample, store.history.entries, moduleSettings, context)
        // Menu bar managers on macOS 27 can move an item when its AppKit length changes.
        // Once this controller has applied geometry and length, both are immutable for the
        // rest of the process lifetime. Layout settings stage a different persisted width
        // for the next launch, when it can be applied before the item becomes visible.
        let stagedImage: NSImage
        if currentGeometry != activeGeometry {
            let stagedContext = StatusItemRendering.context(
                button: button,
                appSettings: appSettings,
                moduleSettings: moduleSettings,
                appearance: appearance,
                geometry: currentGeometry
            )
            stagedImage =
                renderContent(
                    store.latestSample,
                    store.history.entries,
                    moduleSettings,
                    stagedContext
                ).image
        } else {
            stagedImage = content.image
        }
        let naturalLength = StatusItemRendering.itemLength(for: stagedImage)
        let committedLength = StatusItemRendering.committedLength(autosaveName: statusItem.autosaveName)
        let settingsChangedAfterInitialRender = lengthSettings.map { $0 != appSettings } ?? false
        let proposedLength =
            settingsChangedAfterInitialRender
            ? StatusItemRendering.roundedLength(naturalLength)
            : StatusItemRendering.normalizedLength(natural: naturalLength, committed: committedLength)
        if proposedLength != committedLength {
            StatusItemRendering.commitLength(proposedLength, autosaveName: statusItem.autosaveName)
        }
        let activeLength = StatusItemRendering.activeLength(applied: appliedLength, proposed: proposedLength)
        button.image = StatusItemRendering.image(content.image, fittedTo: activeLength)
        // CONTRACT: This is the sole production writer of statusItem.length. It may run
        // once per controller lifetime, before the item is made visible. See
        // docs/MACOS27_STATUS_ITEM_SIZING.md before changing this branch.
        // NSStatusItem.variableLength adds AppKit's standard 8-point image inset
        // on both sides. An explicit length makes the rendered canvas authoritative,
        // so the user-controlled spacing can reach zero while each module remains
        // a separate, movable status item.
        if StatusItemRendering.shouldAssignInitialLength(current: appliedLength) {
            statusItem.length = activeLength
            appliedLength = activeLength
            appliedGeometry = currentGeometry
        }
        lengthSettings = appSettings
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

/// Menu bar geometry that becomes immutable after an item first appears.
struct StatusItemGeometry: Equatable {
    let fontSize: Double
    let scale: Double
    let horizontalSpacing: Double
    let fontWeight: MenuBarFontWeight
    let usesCompactLayout: Bool

    init(settings: AppSettings) {
        fontSize = settings.effectiveMenuBarFontSize
        scale = AppSettings.clampedMenuBarScale(settings.menuBarScale)
        horizontalSpacing = min(12, max(0, settings.menuBarSpacing))
        fontWeight = settings.fontWeight
        usesCompactLayout = settings.usesCompactLayout
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

    /// Item lengths are rounded up to this grid so small typography changes cannot move them.
    static let widthStep: CGFloat = 4

    private static let committedLengthRoot = "Barometer.CommittedWidth."
    private static let committedLengthPrefix = "Barometer.CommittedWidth.v3."

    static func committedLengthKey(autosaveName: String) -> String {
        committedLengthPrefix + autosaveName
    }

    /// The width recorded for an item, if it has rendered before.
    static func committedLength(autosaveName: String?) -> CGFloat? {
        guard let autosaveName, !autosaveName.isEmpty else {
            return nil
        }
        let value = UserDefaults.standard.double(forKey: committedLengthKey(autosaveName: autosaveName))
        return value > 0 ? value : nil
    }

    static func commitLength(_ length: CGFloat, autosaveName: String?) {
        guard let autosaveName, !autosaveName.isEmpty else {
            return
        }
        UserDefaults.standard.set(Double(length), forKey: committedLengthKey(autosaveName: autosaveName))
    }

    /// Forgets every recorded width so current renderings can stage replacement widths.
    static func clearCommittedLengths() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(committedLengthRoot) {
            defaults.removeObject(forKey: key)
        }
    }

    /// The length to apply: the recorded width when there is one, otherwise the natural
    /// width rounded up to the grid.
    static func normalizedLength(natural: CGFloat, committed: CGFloat?) -> CGFloat {
        if let committed, committed > 0 {
            return committed
        }
        return roundedLength(natural)
    }

    static func roundedLength(_ natural: CGFloat) -> CGFloat {
        max(widthStep, (natural / widthStep).rounded(.up) * widthStep)
    }

    /// Keeps the live AppKit frame immutable while allowing a new width to be staged.
    static func activeLength(applied: CGFloat?, proposed: CGFloat) -> CGFloat {
        applied ?? proposed
    }

    /// Fits a rendering into a canvas of exactly `length` points: narrower content is centered,
    /// wider content is scaled down proportionally. The image is returned unchanged when it
    /// already matches.
    static func image(_ image: NSImage, fittedTo length: CGFloat) -> NSImage {
        guard abs(length - image.size.width) > 0.01 else {
            return image
        }
        let height = image.size.height
        let scale = min(1, length / max(1, image.size.width))
        let drawnSize = NSSize(width: image.size.width * scale, height: height * scale)
        let fitted = NSImage(size: NSSize(width: length, height: height), flipped: false) { rect in
            let origin = NSPoint(
                x: floor((rect.width - drawnSize.width) / 2),
                y: floor((rect.height - drawnSize.height) / 2)
            )
            image.draw(in: NSRect(origin: origin, size: drawnSize))
            return true
        }
        fitted.isTemplate = image.isTemplate
        return fitted
    }

    static func shouldAssignInitialLength(current: CGFloat?) -> Bool {
        current == nil
    }

    static func visibilityPreferenceKeys(autosaveName: String) -> [String] {
        [
            "NSStatusItem VisibleCC \(autosaveName)",
            "NSStatusItem Visible \(autosaveName)",
        ]
    }

    static func clearInactiveVisibilityPreferences(autosaveName: String?) {
        guard let autosaveName, !autosaveName.isEmpty else {
            return
        }
        for key in visibilityPreferenceKeys(autosaveName: autosaveName) {
            UserDefaults.standard.removeObject(forKey: key)
        }
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
        let geometry = geometry ?? StatusItemGeometry(settings: appSettings)
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
            horizontalSpacing: geometry.horizontalSpacing,
            graphOpacity: appSettings.graphOpacity,
            fontWeight: geometry.fontWeight,
            usesCompactLayout: geometry.usesCompactLayout
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

extension Notification.Name {
    /// Posted after recorded widths are cleared so every item stages its current natural width.
    public static let barometerStageItemWidths = Notification.Name("com.barometer.app.stageItemWidths")
}
