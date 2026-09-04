import Foundation

/// Shared graph styles available to module renderers.
public enum GraphStyle: String, Codable, CaseIterable, Sendable {
    case line
    case area
    case bars
}

/// Built-in complete appearance palettes.
public enum AppearancePreset: String, Codable, CaseIterable, Sendable {
    case system
    case ocean
    case sunset
    case forest
    case neon
    case custom
}

/// Supported menu bar type weights.
public enum MenuBarFontWeight: String, Codable, CaseIterable, Sendable {
    case regular
    case medium
    case semibold
}

/// Persisted choices for the Weather module.
public struct WeatherSettings: Codable, Equatable, Sendable {
    /// Saved locations in user-selected display order.
    public var locations: [Location]

    /// Stable identifier of the location shown in the menu bar.
    public var primaryLocationID: String?

    /// Whether Barometer should request the Mac's current location.
    public var usesCurrentLocation: Bool

    /// Independent weather measurement units.
    public var units: WeatherUnits

    /// Forecast refresh interval, constrained by the UI to 5 through 60 minutes.
    public var refreshIntervalMinutes: Int

    /// Creates Weather settings.
    public init(
        locations: [Location] = [],
        primaryLocationID: String? = nil,
        usesCurrentLocation: Bool = false,
        units: WeatherUnits = .imperial,
        refreshIntervalMinutes: Int = 15
    ) {
        self.locations = locations
        self.primaryLocationID = primaryLocationID
        self.usesCurrentLocation = usesCurrentLocation
        self.units = units
        self.refreshIntervalMinutes = refreshIntervalMinutes
    }

    /// The selected location, falling back to the first saved location.
    public var primaryLocation: Location? {
        locations.first { $0.id == primaryLocationID } ?? locations.first
    }
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

    /// Optional graph-stroke colors, falling back to the normal role.
    public var graphLightColor: String?
    public var graphDarkColor: String?

    /// Optional graph-fill colors, falling back to the graph role.
    public var fillLightColor: String?
    public var fillDarkColor: String?

    /// Optional warning colors, falling back to the application warning role.
    public var warningLightColor: String?
    public var warningDarkColor: String?

    /// Optional critical colors, falling back to the application critical role.
    public var criticalLightColor: String?
    public var criticalDarkColor: String?

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
        darkColor: String = "#6BA4FF",
        graphLightColor: String? = nil,
        graphDarkColor: String? = nil,
        fillLightColor: String? = nil,
        fillDarkColor: String? = nil,
        warningLightColor: String? = nil,
        warningDarkColor: String? = nil,
        criticalLightColor: String? = nil,
        criticalDarkColor: String? = nil
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
        self.graphLightColor = graphLightColor
        self.graphDarkColor = graphDarkColor
        self.fillLightColor = fillLightColor
        self.fillDarkColor = fillDarkColor
        self.warningLightColor = warningLightColor
        self.warningDarkColor = warningDarkColor
        self.criticalLightColor = criticalLightColor
        self.criticalDarkColor = criticalDarkColor
    }
}

/// Versioned application settings persisted as JSON in the app defaults domain.
public struct AppSettings: Codable, Equatable, Sendable {
    /// Current settings schema version.
    public static let currentSchemaVersion = 14

    /// Supported menu bar font-size range in points.
    public static let menuBarFontSizeRange = 9.0...12.0

    /// Schema version encoded in this value.
    public var schemaVersion: Int

    /// Whether normal sampling intervals double while running on battery.
    public var reducesSamplingOnBattery: Bool

    /// Whether renderers produce template images without explicit colors.
    public var isMonochrome: Bool

    /// Whether every module uses the shared application palette.
    public var usesGlobalColors: Bool

    /// Shared light-appearance RGB color encoded as a hexadecimal string.
    public var globalLightColor: String

    /// Shared dark-appearance RGB color encoded as a hexadecimal string.
    public var globalDarkColor: String

    /// Selected built-in theme, or custom after direct role editing.
    public var appearancePreset: AppearancePreset

    /// Shared graph stroke, fill, warning, and critical role colors.
    public var globalGraphLightColor: String
    public var globalGraphDarkColor: String
    public var globalFillLightColor: String
    public var globalFillDarkColor: String
    public var globalWarningLightColor: String
    public var globalWarningDarkColor: String
    public var globalCriticalLightColor: String
    public var globalCriticalDarkColor: String

    /// Shared graph fill/stroke opacity.
    public var graphOpacity: Double

    /// Shared menu bar type weight.
    public var fontWeight: MenuBarFontWeight

    /// Global menu bar font size.
    public var fontSize: Double {
        didSet {
            fontSize = Self.clampedMenuBarFontSize(fontSize)
        }
    }

    /// Per-module settings keyed by stable module identity.
    public var modules: [ModuleID: ModuleSettings]

    /// Weather locations, units, and refresh preferences.
    public var weather: WeatherSettings

    /// Temperature unit used by hardware sensor readouts.
    public var sensorTemperatureUnit: TemperatureUnit

    /// Precision, raw-name, duplicate, and multi-widget choices for Sensors.
    public var sensors: SensorSettings

    /// Interface, unit, privacy, and graph choices for Network.
    public var network: NetworkSettings

    /// Volume selection, filtering, and unit choices for Disks.
    public var disks: DiskSettings

    /// Visibility and warning choices for Battery.
    public var battery: BatterySettings

    /// Clock format, world-clock, and optional calendar choices.
    public var time: TimeSettings

    /// Ordered composition and individual-item visibility for Combined.
    ///
    /// Superseded by `stacks`. Retained so settings written before stacks shipped still decode and
    /// can be migrated; nothing renders from it.
    public var combined: CombinedSettings

    /// Independently movable metric stacks, including disabled tombstones.
    public var stacks: StacksSettings

    /// Version of one-time default presentation migrations already applied.
    public private(set) var presentationDefaultsVersion: Int

    /// Creates settings with production defaults.
    public init(
        schemaVersion: Int = AppSettings.currentSchemaVersion,
        reducesSamplingOnBattery: Bool = true,
        isMonochrome: Bool = true,
        usesGlobalColors: Bool = false,
        globalLightColor: String = "#2F7CF6",
        globalDarkColor: String = "#6BA4FF",
        appearancePreset: AppearancePreset = .system,
        globalGraphLightColor: String = "#2F7CF6",
        globalGraphDarkColor: String = "#6BA4FF",
        globalFillLightColor: String = "#72A8FF",
        globalFillDarkColor: String = "#397FE8",
        globalWarningLightColor: String = "#F59E0B",
        globalWarningDarkColor: String = "#FBBF24",
        globalCriticalLightColor: String = "#DC2626",
        globalCriticalDarkColor: String = "#F87171",
        graphOpacity: Double = 0.85,
        fontWeight: MenuBarFontWeight = .medium,
        fontSize: Double = 12,
        modules: [ModuleID: ModuleSettings] = AppSettings.defaultModules,
        weather: WeatherSettings = WeatherSettings(),
        sensorTemperatureUnit: TemperatureUnit = .celsius,
        sensors: SensorSettings = SensorSettings(),
        network: NetworkSettings = NetworkSettings(),
        disks: DiskSettings = DiskSettings(),
        battery: BatterySettings = BatterySettings(),
        time: TimeSettings = TimeSettings(),
        combined: CombinedSettings = CombinedSettings(),
        stacks: StacksSettings = StacksSettings()
    ) {
        self.schemaVersion = schemaVersion
        self.reducesSamplingOnBattery = reducesSamplingOnBattery
        self.isMonochrome = isMonochrome
        self.usesGlobalColors = usesGlobalColors
        self.globalLightColor = globalLightColor
        self.globalDarkColor = globalDarkColor
        self.appearancePreset = appearancePreset
        self.globalGraphLightColor = globalGraphLightColor
        self.globalGraphDarkColor = globalGraphDarkColor
        self.globalFillLightColor = globalFillLightColor
        self.globalFillDarkColor = globalFillDarkColor
        self.globalWarningLightColor = globalWarningLightColor
        self.globalWarningDarkColor = globalWarningDarkColor
        self.globalCriticalLightColor = globalCriticalLightColor
        self.globalCriticalDarkColor = globalCriticalDarkColor
        self.graphOpacity = graphOpacity
        self.fontWeight = fontWeight
        self.fontSize = Self.clampedMenuBarFontSize(fontSize)
        self.modules = modules
        self.weather = weather
        self.sensorTemperatureUnit = sensorTemperatureUnit
        self.sensors = sensors
        self.network = network
        self.disks = disks
        self.battery = battery
        self.time = time
        self.combined = combined
        self.stacks = stacks
        presentationDefaultsVersion = 3
    }

    /// Default module settings, with CPU and Memory enabled for Phase 1.
    public static var defaultModules: [ModuleID: ModuleSettings] {
        var values = Dictionary(
            uniqueKeysWithValues: ModuleID.allCases.map { module in
                (module, ModuleSettings())
            })
        values[.cpu] = ModuleSettings(isEnabled: true, mode: "stacked", interval: 1)
        values[.memory] = ModuleSettings(isEnabled: true, mode: "stacked", interval: 2)
        values[.gpu] = ModuleSettings(isEnabled: false, mode: "percentage", interval: 1)
        values[.weather] = ModuleSettings(isEnabled: false, mode: "iconTemperature", interval: 900)
        values[.network] = ModuleSettings(isEnabled: false, mode: "twoLine", interval: 1)
        values[.disks] = ModuleSettings(isEnabled: false, mode: "activityGraph", interval: 1)
        values[.sensors] = ModuleSettings(isEnabled: false, mode: "compactStack", interval: 5)
        values[.battery] = ModuleSettings(isEnabled: false, mode: "glyphPercentage", interval: 10)
        values[.time] = ModuleSettings(isEnabled: false, mode: "custom", interval: 60)
        values[.combined] = ModuleSettings(isEnabled: false, mode: "members", interval: 1)
        return values
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case reducesSamplingOnBattery
        case isMonochrome
        case usesGlobalColors
        case globalLightColor
        case globalDarkColor
        case appearancePreset
        case globalGraphLightColor
        case globalGraphDarkColor
        case globalFillLightColor
        case globalFillDarkColor
        case globalWarningLightColor
        case globalWarningDarkColor
        case globalCriticalLightColor
        case globalCriticalDarkColor
        case graphOpacity
        case fontWeight
        case fontSize
        case modules
        case weather
        case sensorTemperatureUnit
        case sensors
        case network
        case disks
        case battery
        case time
        case combined
        case stacks
        case presentationDefaultsVersion
    }

    /// Decodes current settings or migrates the unversioned version 0 shape.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0

        switch version {
        case 0:
            schemaVersion = Self.currentSchemaVersion
            reducesSamplingOnBattery =
                try container.decodeIfPresent(
                    Bool.self,
                    forKey: .reducesSamplingOnBattery
                ) ?? true
            isMonochrome = try container.decodeIfPresent(Bool.self, forKey: .isMonochrome) ?? true
            usesGlobalColors = false
            globalLightColor = "#2F7CF6"
            globalDarkColor = "#6BA4FF"
            appearancePreset = .system
            globalGraphLightColor = "#2F7CF6"
            globalGraphDarkColor = "#6BA4FF"
            globalFillLightColor = "#72A8FF"
            globalFillDarkColor = "#397FE8"
            globalWarningLightColor = "#F59E0B"
            globalWarningDarkColor = "#FBBF24"
            globalCriticalLightColor = "#DC2626"
            globalCriticalDarkColor = "#F87171"
            graphOpacity = 0.85
            fontWeight = .medium
            fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? 12
            modules = Self.defaultModules
            weather = WeatherSettings()
            sensorTemperatureUnit = .celsius
            sensors = SensorSettings()
            network = NetworkSettings()
            disks = DiskSettings()
            battery = BatterySettings()
            time = TimeSettings()
            combined = CombinedSettings()
            stacks = StacksSettings()
            presentationDefaultsVersion = 3
        case 1...Self.currentSchemaVersion:
            schemaVersion = Self.currentSchemaVersion
            reducesSamplingOnBattery = try container.decode(Bool.self, forKey: .reducesSamplingOnBattery)
            isMonochrome = try container.decode(Bool.self, forKey: .isMonochrome)
            usesGlobalColors = try container.decodeIfPresent(Bool.self, forKey: .usesGlobalColors) ?? false
            globalLightColor = try container.decodeIfPresent(String.self, forKey: .globalLightColor) ?? "#2F7CF6"
            globalDarkColor = try container.decodeIfPresent(String.self, forKey: .globalDarkColor) ?? "#6BA4FF"
            appearancePreset =
                try container.decodeIfPresent(
                    AppearancePreset.self,
                    forKey: .appearancePreset
                ) ?? .system
            globalGraphLightColor =
                try container.decodeIfPresent(
                    String.self,
                    forKey: .globalGraphLightColor
                ) ?? globalLightColor
            globalGraphDarkColor =
                try container.decodeIfPresent(
                    String.self,
                    forKey: .globalGraphDarkColor
                ) ?? globalDarkColor
            globalFillLightColor =
                try container.decodeIfPresent(
                    String.self,
                    forKey: .globalFillLightColor
                ) ?? globalGraphLightColor
            globalFillDarkColor =
                try container.decodeIfPresent(
                    String.self,
                    forKey: .globalFillDarkColor
                ) ?? globalGraphDarkColor
            globalWarningLightColor =
                try container.decodeIfPresent(
                    String.self,
                    forKey: .globalWarningLightColor
                ) ?? "#F59E0B"
            globalWarningDarkColor =
                try container.decodeIfPresent(
                    String.self,
                    forKey: .globalWarningDarkColor
                ) ?? "#FBBF24"
            globalCriticalLightColor =
                try container.decodeIfPresent(
                    String.self,
                    forKey: .globalCriticalLightColor
                ) ?? "#DC2626"
            globalCriticalDarkColor =
                try container.decodeIfPresent(
                    String.self,
                    forKey: .globalCriticalDarkColor
                ) ?? "#F87171"
            graphOpacity = try container.decodeIfPresent(Double.self, forKey: .graphOpacity) ?? 0.85
            fontWeight = try container.decodeIfPresent(MenuBarFontWeight.self, forKey: .fontWeight) ?? .medium
            fontSize = try container.decode(Double.self, forKey: .fontSize)
            modules = try container.decode([ModuleID: ModuleSettings].self, forKey: .modules)
            weather = try container.decodeIfPresent(WeatherSettings.self, forKey: .weather) ?? WeatherSettings()
            sensorTemperatureUnit =
                try container.decodeIfPresent(
                    TemperatureUnit.self,
                    forKey: .sensorTemperatureUnit
                ) ?? .celsius
            sensors = try container.decodeIfPresent(SensorSettings.self, forKey: .sensors) ?? SensorSettings()
            network = try container.decodeIfPresent(NetworkSettings.self, forKey: .network) ?? NetworkSettings()
            disks = try container.decodeIfPresent(DiskSettings.self, forKey: .disks) ?? DiskSettings()
            battery = try container.decodeIfPresent(BatterySettings.self, forKey: .battery) ?? BatterySettings()
            time = try container.decodeIfPresent(TimeSettings.self, forKey: .time) ?? TimeSettings()
            combined = try container.decodeIfPresent(CombinedSettings.self, forKey: .combined) ?? CombinedSettings()
            // Settings written before stacks shipped carry only Combined. Its membership becomes
            // stack 1 so the existing Barometer.Combined item keeps its position and contents.
            stacks =
                try container.decodeIfPresent(StacksSettings.self, forKey: .stacks)
                ?? StacksSettings.migrating(
                    from: combined,
                    isCombinedEnabled: modules[.combined]?.isEnabled == true
                )
            presentationDefaultsVersion =
                try container.decodeIfPresent(
                    Int.self,
                    forKey: .presentationDefaultsVersion
                ) ?? 0
            if presentationDefaultsVersion < 1 {
                if modules[.cpu]?.mode == "percentage" {
                    modules[.cpu]?.mode = "stacked"
                }
                if modules[.memory]?.mode == "usedPercentage" {
                    modules[.memory]?.mode = "stacked"
                }
                presentationDefaultsVersion = 1
            }
            if presentationDefaultsVersion < 3 {
                presentationDefaultsVersion = 3
            }
            if modules[.weather]?.mode == "percentage" {
                modules[.weather]?.mode = "iconTemperature"
            }
            if modules[.weather]?.mode == "template" {
                modules[.weather]?.mode = "iconTemperature"
            }
            if version < 5, modules[.network]?.mode == "percentage" {
                modules[.network]?.mode = "twoLine"
            }
            if version < 7, modules[.disks]?.mode == "percentage" {
                modules[.disks]?.mode = "activityGraph"
            }
            if version < 8, modules[.sensors]?.mode == "percentage" {
                modules[.sensors]?.mode = "compactStack"
            }
            if var sensorModule = modules[.sensors] {
                sensorModule.interval = max(5, sensorModule.interval)
                modules[.sensors] = sensorModule
            }
            if let batteryMode = modules[.battery]?.mode {
                switch batteryMode {
                case "glyphPercentage", "labeledPercentage", "labeledTime", "percentageTime": break
                // The icon-and-time line was too cramped to read; its users keep the time as a
                // second row instead.
                case "glyphTime": modules[.battery]?.mode = "percentageTime"
                case "percentage": modules[.battery]?.mode = "labeledPercentage"
                default: modules[.battery]?.mode = "glyphPercentage"
                }
            }
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported settings schema version \(version)"
            )
        }
        fontSize = Self.clampedMenuBarFontSize(fontSize)
    }

    /// Clamps a font size to the range that fits Barometer's fixed-height menu bar canvases.
    public static func clampedMenuBarFontSize(_ value: Double) -> Double {
        min(menuBarFontSizeRange.upperBound, max(menuBarFontSizeRange.lowerBound, value))
    }

    /// Number of independently movable Barometer items requested by the current settings.
    public var enabledMenuBarItemCount: Int {
        var count = enabledStacks.count
        let hidden = hiddenBySourceStacks

        for module in ModuleID.allCases where module != .combined && module != .sensors {
            if modules[module]?.isEnabled == true && !hidden.contains(module) {
                count += 1
            }
        }

        if modules[.sensors]?.isEnabled == true && !hidden.contains(.sensors) {
            count += sensors.widgets.count(where: \.isEnabled)
        }
        return count
    }

    /// Whether the stacks master switch is on.
    public var areStacksEnabled: Bool {
        modules[.combined]?.isEnabled == true
    }

    /// Stacks that currently own an independently movable status item.
    public var enabledStacks: [StackSettings] {
        areStacksEnabled ? stacks.stacks.filter(\.isEnabled) : []
    }

    /// Modules whose individual status items an enabled stack replaces.
    public var hiddenBySourceStacks: Set<ModuleID> {
        areStacksEnabled ? stacks.hiddenSourceModules : []
    }

    /// Automatic font size selected from the number of independently movable widgets.
    public var effectiveMenuBarFontSize: Double {
        Self.maximumMenuBarFontSize(forItemCount: enabledMenuBarItemCount)
    }

    /// Icon and graph scale reduced automatically as independently movable widgets are added.
    public var effectiveMenuBarScale: Double {
        Self.menuBarScale(forItemCount: enabledMenuBarItemCount)
    }

    /// Automatic graphic scale used for a given number of independently movable items.
    public static func menuBarScale(forItemCount count: Int) -> Double {
        switch count {
        case ...3: 1.15
        case 4...6: 1
        case 7...8: 0.9
        case 9...11: 0.85
        case 12...14: 0.8
        default: 0.75
        }
    }

    /// Automatic font size used for a given number of independently movable items.
    public static func maximumMenuBarFontSize(forItemCount count: Int) -> Double {
        switch count {
        case ...8: 12
        case 9...11: 11
        case 12...14: 10
        default: 9
        }
    }

    /// Resolves the light-appearance color for a module under the global palette policy.
    public func lightColor(for moduleSettings: ModuleSettings) -> String {
        usesGlobalColors ? globalLightColor : moduleSettings.lightColor
    }

    /// Resolves the dark-appearance color for a module under the global palette policy.
    public func darkColor(for moduleSettings: ModuleSettings) -> String {
        usesGlobalColors ? globalDarkColor : moduleSettings.darkColor
    }

    /// Resolves the light graph-stroke role.
    public func graphLightColor(for moduleSettings: ModuleSettings) -> String {
        usesGlobalColors ? globalGraphLightColor : moduleSettings.graphLightColor ?? moduleSettings.lightColor
    }

    /// Resolves the dark graph-stroke role.
    public func graphDarkColor(for moduleSettings: ModuleSettings) -> String {
        usesGlobalColors ? globalGraphDarkColor : moduleSettings.graphDarkColor ?? moduleSettings.darkColor
    }

    /// Resolves the light graph-fill role.
    public func fillLightColor(for moduleSettings: ModuleSettings) -> String {
        usesGlobalColors
            ? globalFillLightColor
            : moduleSettings.fillLightColor ?? graphLightColor(for: moduleSettings)
    }

    /// Resolves the dark graph-fill role.
    public func fillDarkColor(for moduleSettings: ModuleSettings) -> String {
        usesGlobalColors
            ? globalFillDarkColor
            : moduleSettings.fillDarkColor ?? graphDarkColor(for: moduleSettings)
    }

    /// Resolves the light warning role.
    public func warningLightColor(for moduleSettings: ModuleSettings) -> String {
        usesGlobalColors ? globalWarningLightColor : moduleSettings.warningLightColor ?? globalWarningLightColor
    }

    /// Resolves the dark warning role.
    public func warningDarkColor(for moduleSettings: ModuleSettings) -> String {
        usesGlobalColors ? globalWarningDarkColor : moduleSettings.warningDarkColor ?? globalWarningDarkColor
    }

    /// Resolves the light critical role.
    public func criticalLightColor(for moduleSettings: ModuleSettings) -> String {
        usesGlobalColors ? globalCriticalLightColor : moduleSettings.criticalLightColor ?? globalCriticalLightColor
    }

    /// Resolves the dark critical role.
    public func criticalDarkColor(for moduleSettings: ModuleSettings) -> String {
        usesGlobalColors ? globalCriticalDarkColor : moduleSettings.criticalDarkColor ?? globalCriticalDarkColor
    }

    /// Applies one complete built-in theme without modifying module-specific saved colors.
    public mutating func applyTheme(_ preset: AppearancePreset) {
        appearancePreset = preset
        guard preset != .custom else { return }
        isMonochrome = preset == .system
        usesGlobalColors = preset != .system
        let roles: (String, String, String, String, String, String, String, String, String, String)
        switch preset {
        case .system:
            roles = (
                "#2F7CF6", "#6BA4FF", "#2F7CF6", "#6BA4FF", "#72A8FF", "#397FE8",
                "#F59E0B", "#FBBF24", "#DC2626", "#F87171"
            )
        case .ocean:
            roles = (
                "#1677FF", "#70B7FF", "#00A7C7", "#5EE5FF", "#68D5E8", "#147EA3",
                "#F59E0B", "#FBBF24", "#DC2626", "#F87171"
            )
        case .sunset:
            roles = (
                "#C241A7", "#FF8BD8", "#F97316", "#FDBA74", "#FB7185", "#BE185D",
                "#F59E0B", "#FBBF24", "#B91C1C", "#FB7185"
            )
        case .forest:
            roles = (
                "#16803A", "#72E49A", "#0F9F6E", "#5EE6B8", "#6CCF8D", "#137A54",
                "#D97706", "#FBBF24", "#B91C1C", "#F87171"
            )
        case .neon:
            roles = (
                "#16A34A", "#39FF14", "#0D9488", "#00FFC6", "#65A30D", "#7CFF4D",
                "#CA8A04", "#FACC15", "#DC2626", "#FF3B5C"
            )
        case .custom:
            return
        }
        globalLightColor = roles.0
        globalDarkColor = roles.1
        globalGraphLightColor = roles.2
        globalGraphDarkColor = roles.3
        globalFillLightColor = roles.4
        globalFillDarkColor = roles.5
        globalWarningLightColor = roles.6
        globalWarningDarkColor = roles.7
        globalCriticalLightColor = roles.8
        globalCriticalDarkColor = roles.9
    }
}
