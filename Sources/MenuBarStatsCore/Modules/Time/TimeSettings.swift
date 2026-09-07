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

/// One card of the Time dropdown, in the order the user chooses.
public enum TimeDropdownSection: String, Codable, CaseIterable, Sendable {
    case calendar
    case dayEvents
    case notifications
    case worldClocks
    case sun
    case upcomingEvents

    /// User-facing name shown in Time settings.
    public var displayName: String {
        switch self {
        case .calendar: "Calendar"
        case .dayEvents: "Events on the selected day"
        case .notifications: "Notifications"
        case .worldClocks: "World clocks"
        case .sun: "Sunrise and sunset"
        case .upcomingEvents: "Upcoming events"
        }
    }

    /// Restores a saved order: duplicates dropped, unknown values ignored, missing sections appended.
    public static func normalizedOrder(_ order: [TimeDropdownSection]) -> [TimeDropdownSection] {
        var seen: Set<TimeDropdownSection> = []
        var result = order.filter { seen.insert($0).inserted }
        result.append(contentsOf: allCases.filter { !seen.contains($0) })
        return result
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

    /// Menu bar text size for the clock alone, or nil to follow the global text size.
    ///
    /// The clock is the one item people size on its own, so it may go past the global range.
    public var menuBarFontSize: Double?

    /// Whether the dropdown lists the notifications waiting in macOS Notification Center.
    ///
    /// Reading that list needs Full Disk Access; the dropdown explains the grant when it is missing.
    public var showsNotifications: Bool

    /// Text sizes the clock accepts on its own. Wider than the global range because the clock is one
    /// line of text and stays readable at sizes that would overflow denser items.
    public static let menuBarFontSizeRange = 9.0...14.0

    /// Whether Barometer covers the macOS clock so this clock can stand in for it.
    ///
    /// The cover is an opaque panel over the system clock, so its width is not reclaimed. Locating
    /// the clock needs Accessibility access.
    public var hidesSystemClock: Bool

    /// Hex color painted over the system clock when the menu bar's color cannot be sampled.
    public var systemClockCoverColor: String

    /// Order of the dropdown's cards, top to bottom. Always a full permutation of every section.
    public var dropdownSectionOrder: [TimeDropdownSection] {
        didSet { dropdownSectionOrder = TimeDropdownSection.normalizedOrder(dropdownSectionOrder) }
    }

    /// Height of the dropdown panel in points before its content scrolls.
    public var dropdownHeight: Double {
        didSet { dropdownHeight = Self.clampedDropdownHeight(dropdownHeight) }
    }

    /// Panel heights the dropdown accepts; the panel still never exceeds the screen.
    public static let dropdownHeightRange = 400.0...1000.0

    /// The height the dropdown had before it became adjustable.
    public static let defaultDropdownHeight = 560.0

    /// Creates Time settings.
    public init(
        menuBarTemplate: String = "{time}",
        showsSeconds: Bool = false,
        worldClockIdentifiers: [String] = ["UTC"],
        showsCalendarEvents: Bool = false,
        calendarEventCount: Int = 5,
        calendarWeekStart: CalendarWeekStart = .systemDefault,
        menuBarFontSize: Double? = nil,
        showsNotifications: Bool = false,
        dropdownSectionOrder: [TimeDropdownSection] = TimeDropdownSection.allCases,
        dropdownHeight: Double = TimeSettings.defaultDropdownHeight,
        hidesSystemClock: Bool = false,
        systemClockCoverColor: String = "#000000"
    ) {
        self.menuBarTemplate = menuBarTemplate
        self.showsSeconds = showsSeconds
        self.worldClockIdentifiers = worldClockIdentifiers
        self.showsCalendarEvents = showsCalendarEvents
        self.calendarEventCount = calendarEventCount
        self.calendarWeekStart = calendarWeekStart
        self.menuBarFontSize = menuBarFontSize
        self.showsNotifications = showsNotifications
        self.dropdownSectionOrder = dropdownSectionOrder
        self.dropdownHeight = dropdownHeight
        self.hidesSystemClock = hidesSystemClock
        self.systemClockCoverColor = systemClockCoverColor
        normalize()
    }

    private enum CodingKeys: String, CodingKey {
        case menuBarTemplate
        case showsSeconds
        case worldClockIdentifiers
        case showsCalendarEvents
        case calendarEventCount
        case calendarWeekStart
        case menuBarFontSize
        case showsNotifications
        case dropdownSectionOrder
        case dropdownHeight
        case hidesSystemClock
        case systemClockCoverColor
    }

    /// Decodes saved Time settings, defaulting older files to the system's week order, the global
    /// text size, and no notification list.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        menuBarTemplate = try container.decode(String.self, forKey: .menuBarTemplate)
        showsSeconds = try container.decode(Bool.self, forKey: .showsSeconds)
        worldClockIdentifiers = try container.decode([String].self, forKey: .worldClockIdentifiers)
        showsCalendarEvents = try container.decode(Bool.self, forKey: .showsCalendarEvents)
        calendarEventCount = try container.decode(Int.self, forKey: .calendarEventCount)
        calendarWeekStart =
            try container.decodeIfPresent(CalendarWeekStart.self, forKey: .calendarWeekStart) ?? .systemDefault
        menuBarFontSize = try container.decodeIfPresent(Double.self, forKey: .menuBarFontSize)
        showsNotifications = try container.decodeIfPresent(Bool.self, forKey: .showsNotifications) ?? false
        dropdownSectionOrder =
            try container.decodeIfPresent([TimeDropdownSection].self, forKey: .dropdownSectionOrder)
            ?? TimeDropdownSection.allCases
        dropdownHeight =
            try container.decodeIfPresent(Double.self, forKey: .dropdownHeight) ?? Self.defaultDropdownHeight
        hidesSystemClock = try container.decodeIfPresent(Bool.self, forKey: .hidesSystemClock) ?? false
        systemClockCoverColor =
            try container.decodeIfPresent(String.self, forKey: .systemClockCoverColor) ?? "#000000"
        normalize()
    }

    /// Removes invalid and duplicate world-clock identifiers while preserving order.
    public mutating func normalize() {
        var seen: Set<String> = []
        worldClockIdentifiers = worldClockIdentifiers.filter { identifier in
            TimeZone(identifier: identifier) != nil && seen.insert(identifier).inserted
        }
        calendarEventCount = min(10, max(1, calendarEventCount))
        menuBarFontSize = menuBarFontSize.map(Self.clampedMenuBarFontSize)
        dropdownSectionOrder = TimeDropdownSection.normalizedOrder(dropdownSectionOrder)
        dropdownHeight = Self.clampedDropdownHeight(dropdownHeight)
    }

    /// Clamps a dropdown height to the accepted range.
    public static func clampedDropdownHeight(_ value: Double) -> Double {
        min(dropdownHeightRange.upperBound, max(dropdownHeightRange.lowerBound, value))
    }

    /// Clamps a clock text size to the range the fixed-height menu bar canvas can show.
    public static func clampedMenuBarFontSize(_ value: Double) -> Double {
        min(menuBarFontSizeRange.upperBound, max(menuBarFontSizeRange.lowerBound, value))
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

    /// Clock-only text size, or nil to follow the global text size.
    public var fontSize: Double?

    /// Creates one menu bar clock configuration.
    public init(template: String, showsSeconds: Bool, usesFixedWidth: Bool, fontSize: Double? = nil) {
        self.template = template
        self.showsSeconds = showsSeconds
        self.usesFixedWidth = usesFixedWidth
        self.fontSize = fontSize.map(TimeSettings.clampedMenuBarFontSize)
    }
}
