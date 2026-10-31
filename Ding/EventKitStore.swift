import EventKit

/// The slice of `EKEventStore` Ding uses, so `CalendarStore` can be driven by a fake.
protocol EventStoring: AnyObject {
    var authorizationStatus: EKAuthorizationStatus { get }
    /// The object `.EKEventStoreChanged` is posted with.
    var changeSource: AnyObject { get }
    func requestFullAccess() async throws -> Bool
    func events(from start: Date, to end: Date) -> [EKEvent]
    func eventCalendars() -> [EKCalendar]
    func reset()
}

final class EventKitStore: EventStoring {
    private let store = EKEventStore()

    var authorizationStatus: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .event) }
    var changeSource: AnyObject { store }

    func requestFullAccess() async throws -> Bool { try await store.requestFullAccessToEvents() }

    func events(from start: Date, to end: Date) -> [EKEvent] {
        store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
    }

    func eventCalendars() -> [EKCalendar] { store.calendars(for: .event) }
    func reset() { store.reset() }
}
