import Foundation

/// The weekday that begins the month-calendar grid.
public enum CalendarWeekStart: String, Codable, CaseIterable, Sendable {
    case systemDefault
    case sunday
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    /// User-facing name shown in Time settings.
    public var displayName: String {
        switch self {
        case .systemDefault: "System Default"
        case .sunday: "Sunday"
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        }
    }

    /// Gregorian weekday index, or nil when the system preference should be used.
    public var firstWeekday: Int? {
        switch self {
        case .systemDefault: nil
        case .sunday: 1
        case .monday: 2
        case .tuesday: 3
        case .wednesday: 4
        case .thursday: 5
        case .friday: 6
        case .saturday: 7
        }
    }
}

/// Persisted choices for the Time module.
public struct TimeSettings: Codable, Equatable, Sendable {
    /// Token template rendered in the menu bar.
    public var menuBarTemplate: String

    /// Whether the default time token includes seconds.
    public var showsSeconds: Bool

    /// Time-zone identifiers shown in the dropdown.
    public var worldClockIdentifiers: [String]

    /// Whether upcoming calendar events are included when permission is available.
    public var showsCalendarEvents: Bool

    /// Maximum number of upcoming events shown.
    public var calendarEventCount: Int

    /// Weekday that begins the month calendar, or the system preference.
    public var calendarWeekStart: CalendarWeekStart

    /// Whether a primary click on the clock opens macOS Notification Center instead of the dropdown.
    ///
    /// The dropdown stays reachable through a secondary click. Opening Notification Center needs
    /// Accessibility access; without it the click falls back to the dropdown.
    public var opensNotificationCenterOnClick: Bool

    /// Creates Time settings.
    public init(
        menuBarTemplate: String = "{time}",
        showsSeconds: Bool = false,
        worldClockIdentifiers: [String] = ["UTC"],
        showsCalendarEvents: Bool = false,
        calendarEventCount: Int = 5,
        calendarWeekStart: CalendarWeekStart = .systemDefault,
        opensNotificationCenterOnClick: Bool = false
    ) {
        self.menuBarTemplate = menuBarTemplate
        self.showsSeconds = showsSeconds
        self.worldClockIdentifiers = worldClockIdentifiers
        self.showsCalendarEvents = showsCalendarEvents
        self.calendarEventCount = calendarEventCount
        self.calendarWeekStart = calendarWeekStart
        self.opensNotificationCenterOnClick = opensNotificationCenterOnClick
        normalize()
    }

    private enum CodingKeys: String, CodingKey {
        case menuBarTemplate
        case showsSeconds
        case worldClockIdentifiers
        case showsCalendarEvents
        case calendarEventCount
        case calendarWeekStart
        case opensNotificationCenterOnClick
    }

    /// Decodes saved Time settings, defaulting older files to the system's week order and to the dropdown on click.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        menuBarTemplate = try container.decode(String.self, forKey: .menuBarTemplate)
        showsSeconds = try container.decode(Bool.self, forKey: .showsSeconds)
        worldClockIdentifiers = try container.decode([String].self, forKey: .worldClockIdentifiers)
        showsCalendarEvents = try container.decode(Bool.self, forKey: .showsCalendarEvents)
        calendarEventCount = try container.decode(Int.self, forKey: .calendarEventCount)
        calendarWeekStart =
            try container.decodeIfPresent(CalendarWeekStart.self, forKey: .calendarWeekStart) ?? .systemDefault
        opensNotificationCenterOnClick =
            try container.decodeIfPresent(Bool.self, forKey: .opensNotificationCenterOnClick) ?? false
        normalize()
    }

    /// Removes invalid and duplicate world-clock identifiers while preserving order.
    public mutating func normalize() {
        var seen: Set<String> = []
        worldClockIdentifiers = worldClockIdentifiers.filter { identifier in
            TimeZone(identifier: identifier) != nil && seen.insert(identifier).inserted
        }
        calendarEventCount = min(10, max(1, calendarEventCount))
    }
}

/// Width-affecting Time choices that are applied together on a clean application launch.
public struct TimeMenuBarConfiguration: Equatable, Sendable {
    /// Token template rendered in the menu bar.
    public var template: String

    /// Whether clock tokens include seconds.
    public var showsSeconds: Bool

    /// Whether the renderer reserves the configured clock's widest value.
    public var usesFixedWidth: Bool

    /// Creates one menu bar clock configuration.
    public init(template: String, showsSeconds: Bool, usesFixedWidth: Bool) {
        self.template = template
        self.showsSeconds = showsSeconds
        self.usesFixedWidth = usesFixedWidth
    }
}
