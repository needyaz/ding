import XCTest
import UserNotifications
import DingCore
@testable import Ding

final class NotificationRequestTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()

    private let link = MeetingLink(service: .teams, url: URL(string: "https://teams.microsoft.com/l/meetup-join/x")!)

    private func planned(sound: Bool = true, join: Bool = true, link: MeetingLink? = nil) -> PlannedNotification {
        let fire = calendar.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 9, minute: 55))!
        let e = DingEvent(id: "a@1", title: "Standup", start: fire.addingTimeInterval(300), end: fire.addingTimeInterval(2100), link: link)
        let plan = [ScheduledAlert(eventID: "a@1", kind: .notification, fireDate: fire)]
        return NotificationPlanner.build(plan, events: [e], leadMinutes: 5, playSound: sound, joinAction: join)[0]
    }

    func testContentFields() {
        let request = UserNotificationScheduler.makeRequest(for: planned(link: link), calendar: calendar)
        XCTAssertEqual(request.identifier, "ding.a@1")
        XCTAssertEqual(request.content.title, "Standup")
        XCTAssertEqual(request.content.body, "Starts in 5 minutes · Microsoft Teams")
        XCTAssertEqual(request.content.categoryIdentifier, UserNotificationScheduler.category)
        XCTAssertEqual(request.content.userInfo["url"] as? String, link.url.absoluteString)
        XCTAssertEqual(request.content.userInfo["service"] as? String, "teams")
        XCTAssertNotNil(request.content.sound)
    }

    func testTriggerFiresAtTheWallClockTimeOnce() throws {
        let request = UserNotificationScheduler.makeRequest(for: planned(link: link), calendar: calendar)
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertFalse(trigger.repeats)
        XCTAssertEqual(trigger.dateComponents.hour, 9)
        XCTAssertEqual(trigger.dateComponents.minute, 55)
        XCTAssertEqual(trigger.dateComponents.day, 30)
        XCTAssertEqual(trigger.dateComponents.month, 10)
    }

    func testSoundAndJoinActionFollowSettings() {
        let quiet = UserNotificationScheduler.makeRequest(for: planned(sound: false, join: false, link: link), calendar: calendar)
        XCTAssertNil(quiet.content.sound)
        XCTAssertEqual(quiet.content.categoryIdentifier, "")
    }

    func testEventsWithoutLinksCarryNoUserInfoOrJoinButton() {
        let request = UserNotificationScheduler.makeRequest(for: planned(link: nil), calendar: calendar)
        XCTAssertTrue(request.content.userInfo.isEmpty)
        XCTAssertEqual(request.content.categoryIdentifier, "")
        XCTAssertEqual(request.content.body, "Starts in 5 minutes")
    }

    func testLinkRoundTripsThroughUserInfo() {
        let request = UserNotificationScheduler.makeRequest(for: planned(link: link), calendar: calendar)
        XCTAssertEqual(UserNotificationScheduler.link(from: request.content.userInfo), link)
    }

    func testLinkParsingRejectsIncompleteOrBadPayloads() {
        XCTAssertNil(UserNotificationScheduler.link(from: [:]))
        XCTAssertNil(UserNotificationScheduler.link(from: ["url": "https://zoom.us/j/1"]))
        XCTAssertNil(UserNotificationScheduler.link(from: ["service": "zoom"]))
        XCTAssertNil(UserNotificationScheduler.link(from: ["url": "https://zoom.us/j/1", "service": "skype"]))
        XCTAssertNil(UserNotificationScheduler.link(from: ["url": 42, "service": "zoom"]))
    }

    func testClickingOrJoiningOpensTheLinkButDismissingDoesNot() {
        let info: [AnyHashable: Any] = ["url": link.url.absoluteString, "service": "teams"]
        XCTAssertEqual(UserNotificationScheduler.linkToJoin(actionIdentifier: UserNotificationScheduler.joinAction, userInfo: info), link)
        XCTAssertEqual(UserNotificationScheduler.linkToJoin(actionIdentifier: UNNotificationDefaultActionIdentifier, userInfo: info), link)
        XCTAssertNil(UserNotificationScheduler.linkToJoin(actionIdentifier: UNNotificationDismissActionIdentifier, userInfo: info))
        XCTAssertNil(UserNotificationScheduler.linkToJoin(actionIdentifier: UserNotificationScheduler.joinAction, userInfo: [:]))
    }

    func testNotificationsShowAsBannersWithSoundEvenWhenDingIsFrontmost() {
        XCTAssertTrue(UserNotificationScheduler.presentationOptions.contains(.banner))
        XCTAssertTrue(UserNotificationScheduler.presentationOptions.contains(.sound))
    }

    func testJoinActionsAreRecognized() {
        XCTAssertTrue(UserNotificationScheduler.isJoin(actionIdentifier: UserNotificationScheduler.joinAction))
        XCTAssertTrue(UserNotificationScheduler.isJoin(actionIdentifier: UNNotificationDefaultActionIdentifier))
        XCTAssertFalse(UserNotificationScheduler.isJoin(actionIdentifier: UNNotificationDismissActionIdentifier))
        XCTAssertFalse(UserNotificationScheduler.isJoin(actionIdentifier: "something.else"))
    }
}
