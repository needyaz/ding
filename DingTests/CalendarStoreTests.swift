import XCTest
import EventKit
import DingCore
@testable import Ding

@MainActor
final class CalendarStoreFakeTests: XCTestCase {
    private let backing = FakeEventStore()
    private lazy var store = CalendarStore(store: backing)
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testAuthorizationStatusMapping() {
        let cases: [(EKAuthorizationStatus, CalendarAccess)] = [
            (.fullAccess, .granted),
            (.notDetermined, .notDetermined),
            (.denied, .denied),
            (.restricted, .denied),
            (.writeOnly, .denied),
        ]
        for (status, expected) in cases {
            backing.authorizationStatus = status
            XCTAssertEqual(store.access, expected, "\(status.rawValue)")
        }
    }

    func testNothingIsQueriedWithoutAccess() {
        for status in [EKAuthorizationStatus.notDetermined, .denied, .restricted, .writeOnly] {
            backing.authorizationStatus = status
            XCTAssertTrue(store.events(from: start, to: start.addingTimeInterval(3600)).isEmpty)
            XCTAssertTrue(store.accounts().isEmpty)
        }
        XCTAssertTrue(backing.eventQueries.isEmpty)
        XCTAssertEqual(backing.calendarQueries, 0)
    }

    func testEventsAreFetchedForTheRangeAndMapped() {
        let work = backing.makeCalendar("Work")
        backing.stubEvents = [
            backing.makeEvent("Standup", in: work, start: start, location: "https://acme.zoom.us/j/123"),
            backing.makeEvent("Lunch", in: work, start: start.addingTimeInterval(7200)),
        ]
        let end = start.addingTimeInterval(86_400)
        let events = store.events(from: start, to: end)
        XCTAssertEqual(events.map(\.title), ["Standup", "Lunch"])
        XCTAssertEqual(events.first?.link?.service, .zoom)
        XCTAssertNil(events.last?.link)
        XCTAssertEqual(backing.eventQueries.first?.0, start)
        XCTAssertEqual(backing.eventQueries.first?.1, end)
    }

    func testAccountsAreGroupedAndSorted() {
        backing.stubCalendars = [backing.makeCalendar("Zebra"), backing.makeCalendar("apple"), backing.makeCalendar("Mango")]
        let accounts = store.accounts()
        // Fake calendars have no source, so they group under "Other".
        XCTAssertEqual(accounts.map(\.title), ["Other"])
        XCTAssertEqual(accounts.first?.calendars.map(\.title), ["apple", "Mango", "Zebra"])
    }

    func testCalendarInfoCarriesColor() {
        backing.stubCalendars = [backing.makeCalendar("Work", color: NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))]
        let color = store.accounts().first?.calendars.first?.color
        XCTAssertEqual(color?.green ?? 0, 1, accuracy: 0.01)
    }

    func testRequestingAccessResetsTheStoreAndNotifies() async {
        backing.authorizationStatus = .notDetermined
        var changes = 0
        store.onChange = { changes += 1 }
        await store.requestAccess()
        XCTAssertEqual(backing.requests, 1)
        XCTAssertEqual(backing.resets, 1)
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(store.access, .granted)
    }

    func testDeniedRequestLeavesAccessDenied() async {
        backing.authorizationStatus = .notDetermined
        backing.grantOnRequest = false
        await store.requestAccess()
        XCTAssertEqual(store.access, .notDetermined)
        XCTAssertEqual(backing.resets, 1)
    }

    func testAThrowingRequestIsSwallowedAndStillNotifies() async {
        backing.requestThrows = true
        var changes = 0
        store.onChange = { changes += 1 }
        await store.requestAccess()
        XCTAssertEqual(changes, 1)
    }

    func testStoreChangeNotificationsReachOnChange() {
        var changes = 0
        store.onChange = { changes += 1 }
        NotificationCenter.default.post(name: .EKEventStoreChanged, object: backing.changeSource)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(changes, 1)
    }

    func testTheStoreIsResetBeforeAChangeIsReported() {
        // A new account's calendars only show up once cached data is dropped.
        var resetsWhenReported: [Int] = []
        store.onChange = { [unowned self] in resetsWhenReported.append(backing.resets) }
        NotificationCenter.default.post(name: .EKEventStoreChanged, object: backing.changeSource)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(resetsWhenReported, [1])
    }

    func testEveryChangeResetsTheStore() {
        store.onChange = {}
        for _ in 0..<3 { NotificationCenter.default.post(name: .EKEventStoreChanged, object: backing.changeSource) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(backing.resets, 3)
    }

    func testChangesFromOtherStoresAreIgnored() {
        var changes = 0
        store.onChange = { changes += 1 }
        NotificationCenter.default.post(name: .EKEventStoreChanged, object: FakeEventStore())
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(changes, 0)
    }

    func testTheRealEventKitStoreAdapterIsConstructible() {
        let real = EventKitStore()
        XCTAssertNotNil(real.changeSource)
        _ = real.authorizationStatus
    }
}

/// The real EventKit-backed store. Behavior depends on the machine's calendar grant,
/// so these assert consistency rather than specific contents.
@MainActor
final class CalendarStoreTests: XCTestCase {
    func testAccessIsOneOfTheKnownStates() {
        let store = CalendarStore()
        XCTAssertTrue([CalendarAccess.notDetermined, .granted, .denied].contains(store.access))
    }

    func testWithoutAccessNothingIsReturned() {
        let store = CalendarStore()
        guard store.access != .granted else { return }
        XCTAssertTrue(store.events(from: Date(), to: Date().addingTimeInterval(86_400)).isEmpty)
        XCTAssertTrue(store.accounts().isEmpty)
    }

    func testWithAccessQueriesDoNotCrashAndAreOrdered() {
        let store = CalendarStore()
        guard store.access == .granted else { return }
        let events = store.events(from: Date(), to: Date().addingTimeInterval(14 * 86_400))
        XCTAssertTrue(events.allSatisfy { $0.end >= $0.start })
        let accounts = store.accounts()
        let titles = accounts.map(\.title)
        XCTAssertEqual(titles, titles.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    func testChangeCallbackIsSettable() {
        let store = CalendarStore()
        var called = false
        store.onChange = { called = true }
        store.onChange?()
        XCTAssertTrue(called)
    }

    func testAccountAndCalendarIdentity() {
        let calendar = CalendarInfo(id: "1", title: "Home", color: .gray)
        XCTAssertEqual(CalendarAccount(title: "iCloud", calendars: [calendar]).id, "iCloud")
        XCTAssertEqual(calendar.id, "1")
    }
}
