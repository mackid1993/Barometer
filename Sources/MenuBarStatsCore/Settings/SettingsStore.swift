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
        if let data = defaults.data(forKey: Self.defaultsKey),
            let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        {
            settings = decoded
        } else {
            settings = AppSettings()
        }
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
        guard AppSettings.menuBarScaleRange.contains(settings.menuBarScale) else {
            throw SettingsImportError.valueOutOfRange("icon and graph size")
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
