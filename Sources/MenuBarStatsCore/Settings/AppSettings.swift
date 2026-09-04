import Foundation

/// Shared graph styles available to module renderers.
public enum GraphStyle: String, Codable, CaseIterable, Sendable {
    case line
    case area
    case bars
}

/// Persisted settings common to every module.
public struct ModuleSettings: Codable, Equatable, Sendable {
    /// Whether the module's individual status item is visible.
    public var isEnabled: Bool

    /// Renderer mode identifier interpreted by the module.
    public var mode: String

    /// Sampling interval in seconds.
    public var interval: Double

    /// Graph drawing style.
    public var graphStyle: GraphStyle

    /// Whether text renderers reserve a stable width.
    public var usesFixedWidth: Bool

    /// Whether dropdowns include process rows.
    public var showsProcesses: Bool

    /// Maximum process rows in a dropdown.
    public var processCount: Int

    /// Light-appearance RGB color encoded as a hexadecimal string.
    public var lightColor: String

    /// Dark-appearance RGB color encoded as a hexadecimal string.
    public var darkColor: String

    /// Creates module settings.
    public init(
        isEnabled: Bool = false,
        mode: String = "percentage",
        interval: Double = 1,
        graphStyle: GraphStyle = .line,
        usesFixedWidth: Bool = true,
        showsProcesses: Bool = true,
        processCount: Int = 5,
        lightColor: String = "#2F7CF6",
        darkColor: String = "#6BA4FF"
    ) {
        self.isEnabled = isEnabled
        self.mode = mode
        self.interval = interval
        self.graphStyle = graphStyle
        self.usesFixedWidth = usesFixedWidth
        self.showsProcesses = showsProcesses
        self.processCount = processCount
        self.lightColor = lightColor
        self.darkColor = darkColor
    }
}

/// Versioned application settings persisted as JSON in the app defaults domain.
public struct AppSettings: Codable, Equatable, Sendable {
    /// Current settings schema version.
    public static let currentSchemaVersion = 1

    /// Schema version encoded in this value.
    public var schemaVersion: Int

    /// Whether normal sampling intervals double while running on battery.
    public var reducesSamplingOnBattery: Bool

    /// Whether renderers produce template images without explicit colors.
    public var isMonochrome: Bool

    /// Global menu bar font size.
    public var fontSize: Double

    /// Per-module settings keyed by stable module identity.
    public var modules: [ModuleID: ModuleSettings]

    /// Creates settings with production defaults.
    public init(
        schemaVersion: Int = AppSettings.currentSchemaVersion,
        reducesSamplingOnBattery: Bool = true,
        isMonochrome: Bool = true,
        fontSize: Double = 11,
        modules: [ModuleID: ModuleSettings] = AppSettings.defaultModules
    ) {
        self.schemaVersion = schemaVersion
        self.reducesSamplingOnBattery = reducesSamplingOnBattery
        self.isMonochrome = isMonochrome
        self.fontSize = fontSize
        self.modules = modules
    }

    /// Default module settings, with CPU and Memory enabled for Phase 1.
    public static var defaultModules: [ModuleID: ModuleSettings] {
        var values = Dictionary(uniqueKeysWithValues: ModuleID.allCases.map { module in
            (module, ModuleSettings())
        })
        values[.cpu] = ModuleSettings(isEnabled: true, interval: 1)
        values[.memory] = ModuleSettings(isEnabled: true, mode: "usedPercentage", interval: 2)
        return values
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case reducesSamplingOnBattery
        case isMonochrome
        case fontSize
        case modules
    }

    /// Decodes current settings or migrates the unversioned version 0 shape.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0

        switch version {
        case 0:
            schemaVersion = Self.currentSchemaVersion
            reducesSamplingOnBattery = try container.decodeIfPresent(
                Bool.self,
                forKey: .reducesSamplingOnBattery
            ) ?? true
            isMonochrome = try container.decodeIfPresent(Bool.self, forKey: .isMonochrome) ?? true
            fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? 11
            modules = Self.defaultModules
        case Self.currentSchemaVersion:
            schemaVersion = version
            reducesSamplingOnBattery = try container.decode(Bool.self, forKey: .reducesSamplingOnBattery)
            isMonochrome = try container.decode(Bool.self, forKey: .isMonochrome)
            fontSize = try container.decode(Double.self, forKey: .fontSize)
            modules = try container.decode([ModuleID: ModuleSettings].self, forKey: .modules)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported settings schema version \(version)"
            )
        }
    }
}
