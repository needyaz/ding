import XCTest
import DingCore
@testable import Ding

@MainActor
final class AppModelTests: IsolatedDefaultsTestCase {
    private var model: AppModel!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            model = AppModel.test()
            model.now = now
        }
    }

    private func event(_ id: String, offset: TimeInterval, minutes: Int = 30, link: Bool = true, allDay: Bool = false, maybe: Bool = false, calendarID: String = "cal") -> DingEvent {
        .test(id, startingIn: offset, from: now, minutes: minutes, link: link, allDay: allDay, maybe: maybe, calendarID: calendarID)
    }

    func testNextEventIsTheEarliestUpcomingTimedEvent() {
        model.events = [event("later", offset: 7200), event("soon", offset: 600), event("allday", offset: -3600, minutes: 1440, allDay: true)]
        XCTAssertEqual(model.nextEvent?.id, "soon")
    }

    func testNoEventsMeansNoNextEventAndIconOnlyMenuBar() {
        model.events = []
        XCTAssertNil(model.nextEvent)
        XCTAssertNil(model.menuBarText)
        XCTAssertTrue(model.groups.isEmpty)
    }

    func testMenuBarTextFollowsPreferences() {
        model.events = [event("a", offset: 720)]
        XCTAssertEqual(model.menuBarText, "Event a in 12m")
        suite.set(false, forKey: Pref.showTitle)
        XCTAssertEqual(model.menuBarText, "in 12m")
        suite.set(false, forKey: Pref.showCountdown)
        XCTAssertNil(model.menuBarText)
    }

    func testVisibleEventsAppliesCalendarSelection() {
        model.events = [event("keep", offset: 600), event("hide", offset: 900, calendarID: "off")]
        Pref.disabledCalendars = ["off"]
        XCTAssertEqual(model.visibleEvents.map(\.id), ["keep"])
        XCTAssertEqual(model.nextEvent?.id, "keep")
    }

    func testHidingEventsWithoutLinksAffectsNextEvent() {
        model.events = [event("plain", offset: 600, link: false), event("linked", offset: 1200)]
        XCTAssertEqual(model.nextEvent?.id, "plain")
        suite.set(false, forKey: Pref.showEventsWithoutLink)
        XCTAssertEqual(model.nextEvent?.id, "linked")
    }

    func testHidingMaybeEvents() {
        model.events = [event("maybe", offset: 600, maybe: true), event("sure", offset: 1200)]
        suite.set(false, forKey: Pref.showMaybe)
        XCTAssertEqual(model.visibleEvents.map(\.id), ["sure"])
    }

    func testGroupsRespectTheRangeSetting() {
        model.events = [event("today", offset: 600), event("fiveDays", offset: 5 * 86_400)]
        suite.set(1, forKey: Pref.rangeDays)
        XCTAssertEqual(model.groups.flatMap(\.events).map(\.id), ["today"])
        suite.set(7, forKey: Pref.rangeDays)
        XCTAssertEqual(model.groups.flatMap(\.events).map(\.id), ["today", "fiveDays"])
    }

    func testNextEventCanSitBeyondTheDropdownRange() {
        model.events = [event("farAway", offset: 5 * 86_400)]
        suite.set(1, forKey: Pref.rangeDays)
        XCTAssertTrue(model.groups.isEmpty)
        XCTAssertEqual(model.nextEvent?.id, "farAway")
    }

    func testCountdownOnlyTodayHidesFutureDays() {
        model.events = [event("future", offset: 3 * 86_400)]
        XCTAssertNotNil(model.menuBarText)
        suite.set(true, forKey: Pref.countdownOnlyToday)
        XCTAssertNil(model.menuBarText)
    }

    func testJoiningAnEventWithoutALinkDoesNothing() {
        model.isMenuPresented = true
        model.join(event("plain", offset: 600, link: false))
        XCTAssertTrue(model.isMenuPresented)
    }

    func testInitialState() {
        let fresh = AppModel.test()
        XCTAssertFalse(fresh.isMenuPresented)
        XCTAssertTrue(fresh.events.isEmpty)
        XCTAssertTrue(fresh.accounts.isEmpty)
        XCTAssertEqual(fresh.prefsVersion, 0)
    }
}
