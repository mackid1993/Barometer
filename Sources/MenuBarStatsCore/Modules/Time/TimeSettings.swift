import Foundation

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

    /// Creates Time settings.
    public init(
        menuBarTemplate: String = "{time}",
        showsSeconds: Bool = false,
        worldClockIdentifiers: [String] = ["UTC"],
        showsCalendarEvents: Bool = false,
        calendarEventCount: Int = 5
    ) {
        self.menuBarTemplate = menuBarTemplate
        self.showsSeconds = showsSeconds
        self.worldClockIdentifiers = worldClockIdentifiers
        self.showsCalendarEvents = showsCalendarEvents
        self.calendarEventCount = calendarEventCount
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
