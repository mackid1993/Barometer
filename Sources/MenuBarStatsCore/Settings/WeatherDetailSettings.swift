import Foundation

/// Sections that can be shown or hidden in a selected day's weather fly-out.
public enum WeatherDetailSection: String, CaseIterable, Sendable {
    case dayMetrics, precipitation, airComfort, hourly, sunMoon, atmosphere
    case hourlyPrecipitation, hourlyAtmosphere, hourlySunlight, hourlyGround

    /// User-facing title shared by settings and section headers.
    public var title: String {
        switch self {
        case .sunMoon: "Sun & Moon"
        case .dayMetrics: "Day at a glance"
        case .precipitation: "Rain, snow & sunshine"
        case .airComfort: "Air & comfort"
        case .atmosphere: "Atmosphere & growing conditions"
        case .hourly: "Hour by hour"
        case .hourlyPrecipitation: "Precipitation & wind"
        case .hourlyAtmosphere: "Sky & atmosphere"
        case .hourlySunlight: "Sunlight"
        case .hourlyGround: "Ground & growing conditions"
        }
    }

    /// Everyday weather starts expanded; advanced conditions stay behind a chevron.
    public var isExpandedByDefault: Bool {
        switch self {
        case .sunMoon, .dayMetrics, .precipitation, .airComfort, .hourly: true
        default: false
        }
    }

    /// Whether this section belongs inside an expanded forecast hour.
    public var isHourlyGroup: Bool {
        switch self {
        case .hourlyPrecipitation, .hourlyAtmosphere, .hourlySunlight, .hourlyGround: true
        default: false
        }
    }
}

/// Display-only preferences; switching to all details preserves the custom selection.
public struct WeatherDetailSettings: Codable, Equatable, Sendable {
    /// Whether every section is visible regardless of the saved custom choices.
    public var showsAll: Bool
    private var hiddenSections: Set<String>

    /// Creates the default presentation with every section available.
    public init(showsAll: Bool = true) {
        self.showsAll = showsAll
        hiddenSections = []
    }

    /// Whether the saved custom selection includes this section.
    public func isSelected(_ section: WeatherDetailSection) -> Bool {
        !hiddenSections.contains(section.rawValue)
    }

    /// Whether this section is currently visible, respecting its parent hourly section.
    public func isVisible(_ section: WeatherDetailSection) -> Bool {
        let selected = showsAll || isSelected(section)
        return selected && (!section.isHourlyGroup || showsAll || isSelected(.hourly))
    }

    /// Updates the custom selection without changing the selected display mode.
    public mutating func setSelected(_ selected: Bool, for section: WeatherDetailSection) {
        if selected { hiddenSections.remove(section.rawValue) } else { hiddenSections.insert(section.rawValue) }
    }

    private enum CodingKeys: String, CodingKey { case showsAll, hiddenSections }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        showsAll = try values.decodeIfPresent(Bool.self, forKey: .showsAll) ?? true
        hiddenSections = try values.decodeIfPresent(Set<String>.self, forKey: .hiddenSections) ?? []
    }
}
