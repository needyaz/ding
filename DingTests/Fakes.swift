import AppKit
import EventKit
import UserNotifications
import DingCore
@testable import Ding

final class RecordingWorkspace: WorkspaceOpening {
    enum Call: Equatable {
        case open(URL)
        case openWith(URL, String)
    }

    var installedApps: Set<String> = []
    var schemeHandlers: Set<String> = []
    private(set) var calls: [Call] = []

    func open(_ url: URL) { calls.append(.open(url)) }

    func open(_ url: URL, withAppBundleID bundleID: String) -> Bool {
        guard installedApps.contains(bundleID) else { return false }
        calls.append(.openWith(url, bundleID))
        return true
    }

    func hasHandler(for url: URL) -> Bool { schemeHandlers.contains(url.scheme ?? "") }
}

final class FakeNotificationCenter: NotificationCenterProviding {
    enum Call: Equatable {
        case install(categoryIDs: [String])
        case authorize(UNAuthorizationOptions)
        case removeAll
        case add(String)
    }

    private(set) var calls: [Call] = []
    private(set) var requests: [UNNotificationRequest] = []
    private(set) var installedDelegate: UNUserNotificationCenterDelegate?
    private(set) var categories: Set<UNNotificationCategory> = []

    func install(delegate: UNUserNotificationCenterDelegate, categories: Set<UNNotificationCategory>) {
        installedDelegate = delegate
        self.categories = categories
        calls.append(.install(categoryIDs: categories.map(\.identifier).sorted()))
    }

    func requestAuthorization(options: UNAuthorizationOptions) { calls.append(.authorize(options)) }
    func removeAllPending() { calls.append(.removeAll) }

    func add(_ request: UNNotificationRequest) {
        requests.append(request)
        calls.append(.add(request.identifier))
    }
}

final class FakeLoginItem: LoginItemService {
    struct Failure: Error {}
    var isEnabled = false
    var shouldFail = false
    private(set) var registers = 0
    private(set) var unregisters = 0

    func register() throws {
        registers += 1
        if shouldFail { throw Failure() }
        isEnabled = true
    }

    func unregister() throws {
        unregisters += 1
        if shouldFail { throw Failure() }
        isEnabled = false
    }
}

final class FakeEventStore: EventStoring {
    struct Denied: Error {}
    private let backing = EKEventStore()

    var authorizationStatus: EKAuthorizationStatus = .fullAccess
    var grantOnRequest = true
    var requestThrows = false
    var stubEvents: [EKEvent] = []
    var stubCalendars: [EKCalendar] = []
    private(set) var eventQueries: [(Date, Date)] = []
    private(set) var calendarQueries = 0
    private(set) var requests = 0
    private(set) var resets = 0

    var changeSource: AnyObject { self }

    func requestFullAccess() async throws -> Bool {
        requests += 1
        if requestThrows { throw Denied() }
        if grantOnRequest { authorizationStatus = .fullAccess }
        return grantOnRequest
    }

    func events(from start: Date, to end: Date) -> [EKEvent] {
        eventQueries.append((start, end))
        return stubEvents
    }

    func eventCalendars() -> [EKCalendar] {
        calendarQueries += 1
        return stubCalendars
    }

    func reset() { resets += 1 }

    // Builders backed by a real (never saved) store.
    func makeCalendar(_ title: String, color: NSColor = .red) -> EKCalendar {
        let calendar = EKCalendar(for: .event, eventStore: backing)
        calendar.title = title
        calendar.color = color
        return calendar
    }

    func makeEvent(_ title: String, in calendar: EKCalendar, start: Date, minutes: Int = 30, location: String? = nil) -> EKEvent {
        let event = EKEvent(eventStore: backing)
        event.calendar = calendar
        event.title = title
        event.startDate = start
        event.endDate = start.addingTimeInterval(Double(minutes) * 60)
        event.location = location
        return event
    }
}

@MainActor
final class FakeCalendar: CalendarSource {
    var access: CalendarAccess = .granted
    var onChange: (() -> Void)?
    var stubEvents: [DingEvent] = []
    var stubAccounts: [CalendarAccount] = []
    var grantOnRequest = true
    private(set) var requestCount = 0
    private(set) var fetchRanges: [(start: Date, end: Date)] = []

    func requestAccess() async {
        requestCount += 1
        if grantOnRequest { access = .granted }
        onChange?()
    }

    func events(from start: Date, to end: Date) -> [DingEvent] {
        fetchRanges.append((start, end))
        return stubEvents
    }

    func accounts() -> [CalendarAccount] { stubAccounts }
}

/// Stands in for the system notification center. Hosted tests run inside the real Ding
/// bundle, so anything scheduled through the real center would reach the user.
@MainActor
final class FakeNotifier: NotificationScheduling {
    private(set) var permissionRequests = 0
    private(set) var replacements: [[PlannedNotification]] = []

    var latest: [PlannedNotification] { replacements.last ?? [] }

    func requestPermission() { permissionRequests += 1 }
    func replaceAll(with notifications: [PlannedNotification]) { replacements.append(notifications) }
}
