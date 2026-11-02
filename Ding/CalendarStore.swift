import AppKit
import EventKit
import DingCore

/// Reads calendars through EventKit: authorization, fetching, and change notifications.
@MainActor
final class CalendarStore: CalendarSource {
    /// Calendars without a source (rare) are grouped here.
    private static let unknownAccountTitle = "Other"

    private let store: EventStoring
    private var changeObserver: NSObjectProtocol?

    var onChange: (() -> Void)?

    var access: CalendarAccess {
        switch store.authorizationStatus {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied  // denied, restricted, and write-only: Ding needs to read events
        }
    }

    init(store: EventStoring? = nil) {
        self.store = store ?? EventKitStore()
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: self.store.changeSource, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.storeDidChange() }
        }
    }

    deinit {
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
    }

    /// EventKit caches what it has read, so after a change (a new account or calendar, say) a read can
    /// return the old list until the store is reset.
    private func storeDidChange() {
        store.reset()
        onChange?()
    }

    func requestAccess() async {
        // A refusal isn't an error to handle: it shows up as `access == .denied` on the next read.
        _ = try? await store.requestFullAccess()
        store.reset()
        onChange?()
    }

    func events(from start: Date, to end: Date) -> [DingEvent] {
        guard access == .granted else { return [] }
        return store.events(from: start, to: end).compactMap(Self.map)
    }

    func accounts() -> [CalendarAccount] {
        guard access == .granted else { return [] }
        let calendarsBySource = Dictionary(grouping: store.eventCalendars()) { $0.source?.title ?? Self.unknownAccountTitle }
        return calendarsBySource
            .map { title, calendars in
                CalendarAccount(title: title, calendars: calendars.map(Self.info).sorted { Self.isOrdered($0.title, $1.title) })
            }
            .sorted { Self.isOrdered($0.title, $1.title) }
    }

    private static func isOrdered(_ a: String, _ b: String) -> Bool {
        a.localizedCaseInsensitiveCompare(b) == .orderedAscending
    }

    // MARK: Mapping

    private static func info(_ calendar: EKCalendar) -> CalendarInfo {
        CalendarInfo(id: calendar.calendarIdentifier, title: calendar.title, color: color(of: calendar))
    }

    /// Nil for events Ding should ignore: canceled, undated, or declined by the user.
    nonisolated static func map(_ event: EKEvent) -> DingEvent? {
        guard event.status != .canceled,
              let start = event.startDate, let end = event.endDate,
              let calendar = event.calendar else { return nil }
        let currentUser = event.attendees?.first(where: \.isCurrentUser)
        if currentUser?.participantStatus == .declined { return nil }

        let identifier = event.eventIdentifier ?? event.calendarItemIdentifier
        return DingEvent(
            // Recurring events share an identifier, so the start disambiguates occurrences.
            id: "\(identifier)@\(Int(start.timeIntervalSince1970))",
            title: event.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled",
            start: start,
            end: end,
            isAllDay: event.isAllDay,
            calendarID: calendar.calendarIdentifier,
            calendarTitle: calendar.title,
            calendarColor: color(of: calendar),
            response: response(for: currentUser?.participantStatus),
            link: MeetingLinkDetector.detect(LinkSource(location: event.location, url: event.url, notes: event.notes))
        )
    }

    /// "Maybe" and "not answered" are the two unconfirmed states; everything else (accepted, delegated, or no attendee
    /// record at all, as on the user's own events) counts as going.
    nonisolated static func response(for status: EKParticipantStatus?) -> ResponseStatus {
        switch status {
        case .tentative: .maybe
        case .pending: .notResponded
        default: .accepted
        }
    }

    nonisolated static func color(of calendar: EKCalendar) -> CalendarColor {
        guard let rgb = calendar.color?.usingColorSpace(.sRGB) else { return .gray }
        return CalendarColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
    }
}
