import Foundation
import OSLog
import Observation

/// Validation errors for settings documents selected by the user.
public enum SettingsImportError: LocalizedError, Equatable {
    case documentTooLarge
    case valueOutOfRange(String)
    case invalidColor(String)

    public var errorDescription: String? {
        switch self {
        case .documentTooLarge:
            "The settings file is larger than 1 MB."
        case .valueOutOfRange(let name):
            "The settings file contains an out-of-range value for \(name)."
        case .invalidColor(let name):
            "The settings file contains an invalid RGB color for \(name)."
        }
    }
}

/// Observable, debounced persistence for application settings.
@MainActor
@Observable
public final class SettingsStore {
    /// The defaults key containing the encoded settings document.
    public static let defaultsKey = "settings"

    /// Current application settings.
    public var settings: AppSettings {
        didSet {
            scheduleSave()
        }
    }

    /// Module visibility choices waiting for the user to apply them.
    public private(set) var pendingModuleVisibility: [ModuleID: Bool] = [:]

    /// Per-widget Sensors visibility choices waiting for the user to apply them.
    public private(set) var pendingSensorWidgetVisibility: [Int: Bool] = [:]

    /// Per-stack visibility choices waiting for the user to apply them.
    public private(set) var pendingStackVisibility: [Int: Bool] = [:]

    /// Stack readings waiting for the user to apply them.
    ///
    /// Staged because a stack's readings decide which modules it replaces, and that changes the set
    /// of independently visible items.
    public private(set) var pendingStackMetrics: [Int: [StackMetric]] = [:]

    /// Whether a stack should replace the individual items it draws from.
    public private(set) var pendingStackHidesSourceItems: [Int: Bool] = [:]

    /// Menu bar font size captured from the complete saved widget set at launch.
    @ObservationIgnored public let launchMenuBarFontSize: Double

    /// Menu bar graphic scale captured from the complete saved widget set at launch.
    @ObservationIgnored public let launchMenuBarScale: Double

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let encoder = JSONEncoder()
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(
        subsystem: "com.barometer.app",
        category: "settings"
    )

    /// Creates a settings store backed by the supplied defaults suite.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let initialSettings: AppSettings
        if let data = defaults.data(forKey: Self.defaultsKey),
            let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        {
            initialSettings = decoded
        } else {
            initialSettings = AppSettings()
        }
        settings = initialSettings
        launchMenuBarFontSize = initialSettings.effectiveMenuBarFontSize
        launchMenuBarScale = initialSettings.effectiveMenuBarScale
    }

    deinit {
        saveTask?.cancel()
    }

    /// Replaces the current settings with a decoded JSON document.
    public func importJSON(_ data: Data) throws {
        guard data.count <= 1_048_576 else {
            throw SettingsImportError.documentTooLarge
        }
        let imported = try JSONDecoder().decode(AppSettings.self, from: data)
        try Self.validate(imported)
        settings = imported
        discardPendingMenuBarChanges()
    }

    /// Encodes the current settings for export.
    public func exportJSON() throws -> Data {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(settings)
    }

    /// Immediately writes current settings, canceling any pending debounce.
    public func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        do {
            defaults.set(try encoder.encode(settings), forKey: Self.defaultsKey)
        } catch {
            let message = "Unable to encode settings: \(String(describing: error))"
            logger.error("\(message, privacy: .public)")
        }
    }

    /// Settings including staged visibility choices, used by Settings previews and automatic sizing text.
    public var settingsIncludingPendingMenuBarChanges: AppSettings {
        var result = settings
        applyPendingVisibility(to: &result)
        return result
    }

    /// Whether at least one staged visibility choice differs from the saved configuration.
    public var hasPendingMenuBarChanges: Bool {
        !pendingModuleVisibility.isEmpty
            || !pendingSensorWidgetVisibility.isEmpty
            || !pendingStackVisibility.isEmpty
            || !pendingStackMetrics.isEmpty
            || !pendingStackHidesSourceItems.isEmpty
    }

    /// Returns the staged module visibility, falling back to the saved value.
    public func menuBarVisibility(for module: ModuleID) -> Bool {
        pendingModuleVisibility[module] ?? settings.modules[module]?.isEnabled ?? false
    }

    /// Stages a module visibility choice without changing live status items.
    public func stageMenuBarVisibility(_ isVisible: Bool, for module: ModuleID) {
        let savedValue = settings.modules[module]?.isEnabled ?? false
        if isVisible == savedValue {
            pendingModuleVisibility.removeValue(forKey: module)
        } else {
            pendingModuleVisibility[module] = isVisible
        }
    }

    /// Returns the staged Sensors widget visibility, falling back to the saved value.
    public func sensorWidgetVisibility(for id: Int) -> Bool {
        pendingSensorWidgetVisibility[id] ?? settings.sensors.widget(id: id)?.isEnabled ?? false
    }

    /// Stages visibility for one independently movable Sensors widget.
    public func stageSensorWidgetVisibility(_ isVisible: Bool, for id: Int) {
        let savedValue = settings.sensors.widget(id: id)?.isEnabled ?? false
        if isVisible == savedValue {
            pendingSensorWidgetVisibility.removeValue(forKey: id)
        } else {
            pendingSensorWidgetVisibility[id] = isVisible
        }
    }

    /// Returns the staged visibility of one stack, falling back to the saved value.
    public func stackVisibility(for id: Int) -> Bool {
        pendingStackVisibility[id] ?? settings.stacks.stack(id: id)?.isEnabled ?? false
    }

    /// Stages visibility for one independently movable stack.
    public func stageStackVisibility(_ isVisible: Bool, for id: Int) {
        if isVisible == settings.stacks.stack(id: id)?.isEnabled {
            pendingStackVisibility.removeValue(forKey: id)
        } else {
            pendingStackVisibility[id] = isVisible
        }
    }

    /// Returns the staged readings of one stack, falling back to the saved value.
    public func stackMetrics(for id: Int) -> [StackMetric] {
        pendingStackMetrics[id] ?? settings.stacks.stack(id: id)?.metrics ?? []
    }

    /// Stages the readings shown by one stack.
    public func stageStackMetrics(_ metrics: [StackMetric], for id: Int) {
        if metrics == settings.stacks.stack(id: id)?.metrics {
            pendingStackMetrics.removeValue(forKey: id)
        } else {
            pendingStackMetrics[id] = metrics
        }
    }

    /// Returns whether one stack is staged to replace the items it draws from.
    public func stackHidesSourceItems(for id: Int) -> Bool {
        pendingStackHidesSourceItems[id] ?? settings.stacks.stack(id: id)?.hidesSourceItems ?? false
    }

    /// Stages whether one stack replaces the individual items it draws from.
    public func stageStackHidesSourceItems(_ hidesSourceItems: Bool, for id: Int) {
        if hidesSourceItems == settings.stacks.stack(id: id)?.hidesSourceItems {
            pendingStackHidesSourceItems.removeValue(forKey: id)
        } else {
            pendingStackHidesSourceItems[id] = hidesSourceItems
        }
    }

    /// Drops every staged choice for a stack the user deleted.
    public func forgetStack(_ id: Int) {
        pendingStackVisibility.removeValue(forKey: id)
        pendingStackMetrics.removeValue(forKey: id)
        pendingStackHidesSourceItems.removeValue(forKey: id)
    }

    /// Commits all staged visibility choices and persists them immediately.
    public func applyPendingMenuBarChanges() {
        guard hasPendingMenuBarChanges else { return }
        var updated = settings
        applyPendingVisibility(to: &updated)
        clearPendingMenuBarChanges()
        settings = updated
        saveNow()
    }

    /// Removes all uncommitted visibility choices.
    public func discardPendingMenuBarChanges() {
        clearPendingMenuBarChanges()
    }

    private func clearPendingMenuBarChanges() {
        pendingModuleVisibility.removeAll()
        pendingSensorWidgetVisibility.removeAll()
        pendingStackVisibility.removeAll()
        pendingStackMetrics.removeAll()
        pendingStackHidesSourceItems.removeAll()
    }

    private func applyPendingVisibility(to result: inout AppSettings) {
        for (module, isVisible) in pendingModuleVisibility {
            var moduleSettings = result.modules[module] ?? ModuleSettings()
            moduleSettings.isEnabled = isVisible
            result.modules[module] = moduleSettings
        }
        for (id, isVisible) in pendingSensorWidgetVisibility {
            guard let index = result.sensors.widgets.firstIndex(where: { $0.id == id }) else { continue }
            result.sensors.widgets[index].isEnabled = isVisible
        }
        for (id, isVisible) in pendingStackVisibility {
            guard let index = result.stacks.stacks.firstIndex(where: { $0.id == id }) else { continue }
            result.stacks.stacks[index].isEnabled = isVisible
        }
        for (id, metrics) in pendingStackMetrics {
            guard let index = result.stacks.stacks.firstIndex(where: { $0.id == id }) else { continue }
            result.stacks.stacks[index].metrics = metrics
        }
        for (id, hidesSourceItems) in pendingStackHidesSourceItems {
            guard let index = result.stacks.stacks.firstIndex(where: { $0.id == id }) else { continue }
            result.stacks.stacks[index].hidesSourceItems = hidesSourceItems
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            self?.saveNow()
        }
    }

    private static func validate(_ settings: AppSettings) throws {
        guard AppSettings.menuBarFontSizeRange.contains(settings.fontSize) else {
            throw SettingsImportError.valueOutOfRange("font size")
        }
        guard (0.1...1).contains(settings.graphOpacity) else {
            throw SettingsImportError.valueOutOfRange("graph opacity")
        }
        guard settings.weather.refreshIntervalMinutes >= 5 else {
            throw SettingsImportError.valueOutOfRange("weather refresh interval")
        }
        guard settings.modules.values.allSatisfy({ $0.interval >= 0.25 && $0.processCount > 0 }) else {
            throw SettingsImportError.valueOutOfRange("module sampling or process count")
        }
        if let globalInterval = settings.globalSamplingInterval,
           !(0.5...60).contains(globalInterval) {
            throw SettingsImportError.valueOutOfRange("global sampling interval")
        }

        let globalColors = [
            settings.globalLightColor, settings.globalDarkColor,
            settings.globalGraphLightColor, settings.globalGraphDarkColor,
            settings.globalFillLightColor, settings.globalFillDarkColor,
            settings.globalWarningLightColor, settings.globalWarningDarkColor,
            settings.globalCriticalLightColor, settings.globalCriticalDarkColor,
        ]
        guard globalColors.allSatisfy(isRGBHex) else {
            throw SettingsImportError.invalidColor("global appearance")
        }
        for module in settings.modules.values {
            let colors =
                [module.lightColor, module.darkColor]
                + [
                    module.graphLightColor, module.graphDarkColor, module.fillLightColor, module.fillDarkColor,
                    module.warningLightColor, module.warningDarkColor, module.criticalLightColor,
                    module.criticalDarkColor,
                ].compactMap { $0 }
            guard colors.allSatisfy(isRGBHex) else {
                throw SettingsImportError.invalidColor("module appearance")
            }
        }
    }

    private static func isRGBHex(_ value: String) -> Bool {
        let characters = value.hasPrefix("#") ? value.dropFirst() : Substring(value)
        return characters.count == 6 && characters.allSatisfy(\.isHexDigit)
    }
}
