#if DEBUG
import AppKit
import SwiftUI
import XCTest
import DingCore
@testable import Ding

/// The screenshot mode is dev tooling, but it feeds the App Store listing, so its fixtures and output shape are pinned.
@MainActor
final class ScreenshotTests: XCTestCase {
    private let allowedMacSizes: [(Int, Int)] = [(1280, 800), (1440, 900), (2560, 1600), (2880, 1800)]

    // MARK: Output shape

    func testTheDeliveredSizeIsOneTheMacAppStoreAccepts() {
        let size = ScreenshotMode.pixelSize
        XCTAssertTrue(allowedMacSizes.contains { $0.0 == Int(size.width) && $0.1 == Int(size.height) }, "\(size)")
    }

    func testScenesAreLaidOutSixteenByTenAndScaleToTheDeliveredSize() {
        let points = ScreenshotMode.pointSize
        XCTAssertEqual(points.width / points.height, 1.6, accuracy: 0.0001)
        XCTAssertEqual(points.width * ScreenshotMode.scale, ScreenshotMode.pixelSize.width, accuracy: 0.001)
        XCTAssertEqual(points.height * ScreenshotMode.scale, ScreenshotMode.pixelSize.height, accuracy: 0.001)
    }

    func testRenderingProducesAPNGAtTheDeliveredPixelSize() throws {
        let data = try XCTUnwrap(ScreenshotMode.render(Color.red))
        let rep = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(CGFloat(rep.pixelsWide), ScreenshotMode.pixelSize.width)
        XCTAssertEqual(CGFloat(rep.pixelsHigh), ScreenshotMode.pixelSize.height)
        XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47], "a PNG signature")
    }

    func testRenderedPixelsAreTheViewsNotBlank() throws {
        let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(ScreenshotMode.render(Color(red: 1, green: 0, blue: 0)))))
        let color = try XCTUnwrap(rep.colorAt(x: 1440, y: 900)?.usingColorSpace(.sRGB))
        // Not exactly (1, 0, 0): the bitmap is device RGB and the comparison is sRGB.
        XCTAssertGreaterThan(color.redComponent, 0.8)
        XCTAssertLessThan(color.greenComponent, 0.3)
        XCTAssertLessThan(color.blueComponent, 0.3)
    }

    // MARK: Scenes

    func testScenesHaveOrderedUniqueFileNames() {
        let names = ScreenshotScene.all(model: AppModel.test()).map(\.name)
        XCTAssertEqual(names.count, 6)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertEqual(names, names.sorted(), "the store shows them in file-name order")
        for (index, name) in names.enumerated() {
            XCTAssertTrue(name.hasPrefix(String(format: "%02d_", index + 1)), name)
            XCTAssertNotNil(name.wholeMatch(of: /\d\d_[a-z-]+/), name)
        }
    }

    func testEveryTabCanBeShown() {
        XCTAssertEqual(SettingsTab.allCases.count, 6)
        XCTAssertEqual(Set(SettingsTab.allCases.map(\.rawValue)).count, 6)
    }

    // MARK: Fixtures

    func testTheClockIsFrozenOnATuesdayMorning() {
        let parts = Calendar.current.dateComponents([.weekday, .hour, .minute], from: ScreenshotFixtures.now)
        XCTAssertEqual(parts.weekday, 3, "Tuesday")
        XCTAssertEqual(parts.hour, 9)
        XCTAssertEqual(parts.minute, 48)
    }

    func testTheNextMeetingIsTheOneTheCaptionsPromise() throws {
        let next = try XCTUnwrap(NextEvent.select(from: ScreenshotFixtures.events, now: ScreenshotFixtures.now))
        XCTAssertEqual(next.title, "Team standup")
        XCTAssertEqual(Countdown.text(until: next.start, now: ScreenshotFixtures.now), "12m")
        XCTAssertEqual(next.link?.service, .googleMeet)
    }

    func testTheFixtureCalendarShowsEveryKindOfRow() {
        let events = ScreenshotFixtures.events
        XCTAssertTrue(events.contains { $0.isAllDay }, "an all-day row")
        XCTAssertTrue(events.contains { $0.isMaybe }, "a maybe row")
        XCTAssertTrue(events.contains { !$0.hasLink && !$0.isAllDay }, "a row with no link")
        XCTAssertEqual(Set(events.compactMap { $0.link?.service }), [.zoom, .googleMeet, .teams, .webex])
    }

    func testTheFixturesComeFromNowhereReal() {
        for event in ScreenshotFixtures.events {
            if let link = event.link { XCTAssertEqual(link.url.host, "example.com", event.title) }
        }
        let accountCalendarIDs = Set(ScreenshotFixtures.accounts.flatMap(\.calendars).map(\.id))
        XCTAssertTrue(Set(ScreenshotFixtures.events.map(\.calendarID)).isSubset(of: accountCalendarIDs))
    }

    func testTheFixturesSpanAFewDaysAfterNow() {
        let end = ScreenshotFixtures.at(day: 3, hour: 0, minute: 0)
        XCTAssertTrue(ScreenshotFixtures.events.allSatisfy { $0.end > ScreenshotFixtures.now && $0.start < end })
    }

    func testScreenshotPreferencesNeverTouchTheRealOnes() {
        let defaults = ScreenshotFixtures.makeDefaults()
        let real = Pref.defaults
        let keys = [Pref.alertMode, Pref.alertLeadMinutes, Pref.rangeDays, Pref.controlReadSchedule, Pref.controlOpenMeetings, Pref.use24Hour]
        let before = keys.map { real.object(forKey: $0) as? NSObject }
        defer { Pref.defaults = real; defaults.removePersistentDomain(forName: "blue.luci.Ding.screenshots") }
        ScreenshotFixtures.configure(defaults)
        XCTAssertEqual(Pref.alertSettings.mode, .fullScreen, "the screenshots see their own settings")
        XCTAssertTrue(Pref.controlPermissions.canReadSchedule)
        XCTAssertEqual(keys.map { real.object(forKey: $0) as? NSObject }, before, "and the real settings are exactly as they were")
    }

    func testTheFullScreenViewCanShowAFixedMoment() {
        // The screenshots freeze the countdown; the live view still follows the clock when no moment is given.
        let start = ScreenshotFixtures.at(day: 0, hour: 10, minute: 0)
        XCTAssertEqual(EventDisplay.alertStatus(now: start.addingTimeInterval(-59), start: start), "Starts in 0:59")
        let view = FullScreenAlertView(event: ScreenshotFixtures.events[0], join: {}, snooze: {}, dismiss: {}, fixedNow: start)
        XCTAssertEqual(view.fixedNow, start)
        XCTAssertNil(FullScreenAlertView(event: nil, join: {}, snooze: {}, dismiss: {}).fixedNow)
    }
}
#endif
