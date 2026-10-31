import XCTest
import UserNotifications
import DingCore
@testable import Ding

@MainActor
final class UserNotificationSchedulerTests: XCTestCase {
    private let center = FakeNotificationCenter()

    private func planned(_ id: String, minutesFromNow: Double) -> PlannedNotification {
        let fire = Date().addingTimeInterval(minutesFromNow * 60)
        let link = MeetingLink(service: .zoom, url: URL(string: "https://zoom.us/j/1")!)
        return PlannedNotification(id: "ding.\(id)", title: id, body: "Starts in 5 minutes", fireDate: fire, playSound: true, joinAction: true, link: link)
    }

    func testInstallsItselfAsDelegateWithAJoinCategory() throws {
        let scheduler = UserNotificationScheduler(center: center)
        XCTAssertTrue(center.installedDelegate === scheduler)
        let category = try XCTUnwrap(center.categories.first)
        XCTAssertEqual(category.identifier, UserNotificationScheduler.category)
        XCTAssertEqual(category.actions.map(\.identifier), [UserNotificationScheduler.joinAction])
        XCTAssertEqual(category.actions.first?.title, "Join")
    }

    func testRequestsAlertAndSoundPermission() {
        UserNotificationScheduler(center: center).requestPermission()
        XCTAssertTrue(center.calls.contains(.authorize([.alert, .sound])))
    }

    func testReplaceAllClearsBeforeAdding() {
        let scheduler = UserNotificationScheduler(center: center)
        scheduler.replaceAll(with: [planned("a", minutesFromNow: 10), planned("b", minutesFromNow: 20)])
        let afterInstall = Array(center.calls.drop { if case .install = $0 { true } else { false } })
        XCTAssertEqual(afterInstall, [.removeAll, .add("ding.a"), .add("ding.b")])
    }

    func testReplacingWithNothingJustClears() {
        let scheduler = UserNotificationScheduler(center: center)
        scheduler.replaceAll(with: [planned("a", minutesFromNow: 10)])
        scheduler.replaceAll(with: [])
        XCTAssertEqual(center.calls.last, .removeAll)
        XCTAssertEqual(center.requests.count, 1)
    }

    func testRequestsCarryTheBuiltContent() throws {
        UserNotificationScheduler(center: center).replaceAll(with: [planned("standup", minutesFromNow: 30)])
        let request = try XCTUnwrap(center.requests.first)
        XCTAssertEqual(request.identifier, "ding.standup")
        XCTAssertEqual(request.content.title, "standup")
        XCTAssertEqual(request.content.categoryIdentifier, UserNotificationScheduler.category)
        XCTAssertTrue(request.trigger is UNCalendarNotificationTrigger)
    }

    func testSchedulerFeedsTheCenterEndToEnd() throws {
        let scheduler = Scheduler(notifier: UserNotificationScheduler(center: center))
        let start = Date().addingTimeInterval(3600)
        let event = DingEvent(
            id: "e@1", title: "Planning", start: start, end: start.addingTimeInterval(1800),
            link: MeetingLink(service: .googleMeet, url: URL(string: "https://meet.google.com/abc-defg-hij")!)
        )
        scheduler.update(events: [event], next: event, settings: AlertSettings(leadMinutes: 10))
        let request = try XCTUnwrap(center.requests.first)
        XCTAssertEqual(request.content.title, "Planning")
        XCTAssertEqual(request.content.body, "Starts in 10 minutes · Google Meet")
    }
}
