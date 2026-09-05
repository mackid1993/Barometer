import EventKit
import Foundation

/// User-visible Calendar authorization states.
public enum CalendarAuthorizationState: String, Codable, CaseIterable, Equatable, Sendable {
    case notDetermined
    case restricted
    case denied
    case writeOnly
    case fullAccess
    case unavailable
}

/// One immutable upcoming calendar event.
public struct CalendarEventSnapshot: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let isAllDay: Bool
    public let calendarTitle: String

    /// Creates a calendar event snapshot.
    public init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        calendarTitle: String
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.calendarTitle = calendarTitle
    }
}

/// Isolates all EventKit access and never requests permission implicitly.
public actor CalendarEventSource {
    private let store = EKEventStore()

    /// Creates a Calendar source without prompting for permission.
    public init() {}

    /// Current system authorization without any side effect.
    public var authorizationState: CalendarAuthorizationState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .writeOnly: .writeOnly
        case .fullAccess: .fullAccess
        @unknown default: .unavailable
        }
    }

    /// Requests full event access only after a user-initiated UI action.
    @discardableResult
    public func requestFullAccess() async -> CalendarAuthorizationState {
        do {
            _ = try await store.requestFullAccessToEvents()
        } catch {
            return authorizationState
        }
        return authorizationState
    }

    /// Returns upcoming events, or an empty list unless full access has already been granted.
    public func events(from date: Date, limit: Int) -> [CalendarEventSnapshot] {
        guard authorizationState == .fullAccess else { return [] }
        let endDate =
            Calendar.current.date(byAdding: .day, value: 14, to: date)
            ?? date.addingTimeInterval(14 * 86_400)
        let predicate = store.predicateForEvents(withStart: date, end: endDate, calendars: nil)
        return store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .prefix(max(1, limit))
            .map { event in
                CalendarEventSnapshot(
                    id: event.eventIdentifier
                        ?? "\(event.startDate.timeIntervalSinceReferenceDate)-\(event.title ?? "")",
                    title: event.title?.isEmpty == false ? event.title : "Untitled Event",
                    startDate: event.startDate,
                    endDate: event.endDate,
                    isAllDay: event.isAllDay,
                    calendarTitle: event.calendar.title
                )
            }
    }
}
