import Foundation

/// Menu bar presentation modes available to each Sensors widget.
public enum SensorWidgetMode: String, Codable, CaseIterable, Sendable {
    case compactStack
    case text
    case graph
    case fan
}

/// Persisted configuration for one independently movable Sensors status item.
public struct SensorWidgetSettings: Codable, Equatable, Identifiable, Sendable {
    /// Stable one-based instance used by the status item's numbered identity.
    public let id: Int

    /// Whether this status item is visible when the Sensors module is enabled.
    public var isEnabled: Bool

    /// Presentation used by this status item.
    public var mode: SensorWidgetMode

    /// Stable sensor identifiers in user-selected display order.
    public var sensorIDs: [String]

    /// Creates one Sensors widget configuration.
    public init(
        id: Int,
        isEnabled: Bool = true,
        mode: SensorWidgetMode = .compactStack,
        sensorIDs: [String] = ["derived:temperature:hottest", "smc:fan:0"]
    ) {
        self.id = max(1, id)
        self.isEnabled = isEnabled
        self.mode = mode
        self.sensorIDs = sensorIDs
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case isEnabled
        case mode
        case sensorIDs
    }

    /// Decodes older widget records while preserving a valid permanent identity.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = max(1, try container.decodeIfPresent(Int.self, forKey: .id) ?? 1)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        mode = try container.decodeIfPresent(SensorWidgetMode.self, forKey: .mode) ?? .compactStack
        sensorIDs = try container.decodeIfPresent([String].self, forKey: .sensorIDs)
            ?? ["derived:temperature:hottest", "smc:fan:0"]
    }
}

/// Persisted choices specific to hardware sensors and their menu bar widgets.
public struct SensorSettings: Codable, Equatable, Sendable {
    /// Number of fractional digits used for temperatures, watts, volts, and amps.
    public var decimalPlaces: Int

    /// Whether friendly labels also show the data source's raw name.
    public var showsRawNames: Bool

    /// Whether equivalent friendly readings from lower-priority sources are hidden.
    public var hidesDuplicates: Bool

    /// Independently movable Sensors widgets, including disabled tombstones.
    public var widgets: [SensorWidgetSettings]

    /// Creates Sensors settings.
    public init(
        decimalPlaces: Int = 1,
        showsRawNames: Bool = false,
        hidesDuplicates: Bool = true,
        widgets: [SensorWidgetSettings] = [SensorWidgetSettings(id: 1)]
    ) {
        self.decimalPlaces = min(2, max(0, decimalPlaces))
        self.showsRawNames = showsRawNames
        self.hidesDuplicates = hidesDuplicates
        self.widgets = Self.normalized(widgets)
    }

    /// Returns a widget by its permanent instance number.
    public func widget(id: Int) -> SensorWidgetSettings? {
        widgets.first { $0.id == id }
    }

    /// Returns the next never-used instance number.
    public var nextWidgetID: Int {
        (widgets.map(\.id).max() ?? 0) + 1
    }

    private enum CodingKeys: String, CodingKey {
        case decimalPlaces
        case showsRawNames
        case hidesDuplicates
        case widgets
    }

    /// Decodes settings while supplying defaults added after the Sensors module shipped.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        decimalPlaces = min(2, max(0, try container.decodeIfPresent(Int.self, forKey: .decimalPlaces) ?? 1))
        showsRawNames = try container.decodeIfPresent(Bool.self, forKey: .showsRawNames) ?? false
        hidesDuplicates = try container.decodeIfPresent(Bool.self, forKey: .hidesDuplicates) ?? true
        widgets = Self.normalized(
            try container.decodeIfPresent([SensorWidgetSettings].self, forKey: .widgets)
                ?? [SensorWidgetSettings(id: 1)]
        )
    }

    private static func normalized(_ widgets: [SensorWidgetSettings]) -> [SensorWidgetSettings] {
        var seen: Set<Int> = []
        let unique = widgets.filter { seen.insert($0.id).inserted }
        return (unique.isEmpty ? [SensorWidgetSettings(id: 1)] : unique).sorted { $0.id < $1.id }
    }
}
