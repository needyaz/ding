import XCTest
@testable import DingCore

final class MeetingLinkDetectorTests: XCTestCase {
    private func detect(location: String? = nil, url: String? = nil, notes: String? = nil, conference: [String] = []) -> MeetingLink? {
        MeetingLinkDetector.detect(LinkSource(
            conferenceURLs: conference.compactMap(URL.init(string:)),
            location: location,
            url: url.flatMap(URL.init(string:)),
            notes: notes
        ))
    }

    // MARK: Fixture corpus (shapes taken from real invites)

    func testZoomInviteBody() {
        let notes = """
        Hi there,
        Nate is inviting you to a scheduled Zoom meeting.

        Join Zoom Meeting
        https://us02web.zoom.us/j/84512345678?pwd=Qk1hZWxhbmRvbVBhc3M

        Meeting ID: 845 1234 5678
        Passcode: 123456
        One tap mobile
        +16699006833,,84512345678#,,,,*123456# US
        """
        let link = detect(notes: notes)
        XCTAssertEqual(link?.service, .zoom)
        XCTAssertEqual(link?.url.absoluteString, "https://us02web.zoom.us/j/84512345678?pwd=Qk1hZWxhbmRvbVBhc3M")
    }

    func testZoomVanityAndGovHosts() {
        XCTAssertEqual(detect(location: "https://acme.zoom.us/j/123456789")?.service, .zoom)
        XCTAssertEqual(detect(location: "https://acme.zoom.us/my/nate.eide")?.service, .zoom)
        XCTAssertEqual(detect(location: "https://us02web.zoomgov.com/j/1600000000")?.service, .zoom)
        XCTAssertEqual(detect(location: "zoommtg://zoom.us/join?confno=123")?.service, .zoom)
    }

    func testZoomMarketingLinksAreNotMeetings() {
        // Two unknown URLs: not zoom, and ambiguous so no "Other link" either.
        XCTAssertNil(detect(notes: "Need Zoom? https://zoom.us/download and also https://zoom.us/support"))
    }

    func testGoogleMeetFromURLField() {
        let link = detect(url: "https://meet.google.com/abc-defg-hij")
        XCTAssertEqual(link?.service, .googleMeet)
    }

    func testGoogleMeetInGoogleCalendarNotesWithRedirectWrapper() {
        let notes = """
        <b>Join with Google Meet</b>
        <a href="https://www.google.com/url?q=https://meet.google.com/abc-defg-hij&amp;sa=D&amp;source=calendar&amp;usd=2&amp;usg=AOvVaw0">https://meet.google.com/abc-defg-hij</a>
        Or dial: (US) +1 555-0100 PIN: 123 456 789#
        <a href="https://tel.meet/abc-defg-hij?pin=1234">More phone numbers</a>
        """
        let link = detect(notes: notes)
        XCTAssertEqual(link?.service, .googleMeet)
        XCTAssertEqual(link?.url.absoluteString, "https://meet.google.com/abc-defg-hij")
    }

    func testGoogleMeetWithAuthUserQuery() {
        let link = detect(location: "https://meet.google.com/abc-defg-hij?authuser=1")
        XCTAssertEqual(link?.url.absoluteString, "https://meet.google.com/abc-defg-hij?authuser=1")
    }

    func testTeamsInvite() {
        let notes = """
        ________________________________________________________________________________
        Microsoft Teams meeting
        Join on your computer, mobile app or room device
        Click here to join the meeting<https://teams.microsoft.com/l/meetup-join/19%3ameeting_Zm9vYmFy%40thread.v2/0?context=%7b%22Tid%22%3a%22abc%22%7d>
        Meeting ID: 261 123 456 789
        Passcode: AbCdEf
        """
        let link = detect(notes: notes)
        XCTAssertEqual(link?.service, .teams)
        XCTAssertTrue(link!.url.absoluteString.hasPrefix("https://teams.microsoft.com/l/meetup-join/"))
    }

    func testTeamsBehindOutlookSafeLinks() {
        let wrapped = "https://nam06.safelinks.protection.outlook.com/?url=https%3A%2F%2Fteams.microsoft.com%2Fl%2Fmeetup-join%2F19%253ameeting_abc%2540thread.v2%2F0&data=05%7C01&sdata=xyz&reserved=0"
        let link = detect(notes: "Join: \(wrapped)")
        XCTAssertEqual(link?.service, .teams)
        XCTAssertEqual(link?.url.host, "teams.microsoft.com")
    }

    func testTeamsShortMeetLink() {
        XCTAssertEqual(detect(location: "https://teams.microsoft.com/meet/123456789012?p=abc")?.service, .teams)
        XCTAssertEqual(detect(location: "https://teams.live.com/meet/9876543210")?.service, .teams)
    }

    func testWebexLinks() {
        XCTAssertEqual(detect(location: "https://acme.webex.com/acme/j.php?MTID=m123abc")?.service, .webex)
        XCTAssertEqual(detect(notes: "Join: https://acme.webex.com/meet/nate.eide")?.service, .webex)
        XCTAssertEqual(detect(notes: "https://meet123.webex.com/join/nate")?.service, .webex)
    }

    // MARK: Search order

    func testConferenceDataBeatsEverything() {
        let link = detect(
            location: "https://acme.zoom.us/j/111",
            url: "https://meet.google.com/abc-defg-hij",
            notes: "https://acme.webex.com/meet/nate",
            conference: ["https://teams.microsoft.com/l/meetup-join/xyz"]
        )
        XCTAssertEqual(link?.service, .teams)
    }

    func testLocationBeatsURLBeatsNotes() {
        XCTAssertEqual(detect(location: "https://acme.zoom.us/j/111", url: "https://meet.google.com/abc-defg-hij", notes: "https://acme.webex.com/meet/n")?.service, .zoom)
        XCTAssertEqual(detect(url: "https://meet.google.com/abc-defg-hij", notes: "https://acme.webex.com/meet/n")?.service, .googleMeet)
    }

    func testKnownServiceInNotesBeatsOtherURLInLocation() {
        let link = detect(location: "https://example.com/room", notes: "https://acme.zoom.us/j/123")
        XCTAssertEqual(link?.service, .zoom)
    }

    // MARK: Other link fallback

    func testSingleUnknownURLBecomesOtherLink() {
        let link = detect(notes: "Call us on https://whereby.com/acme-standup, see you there.")
        XCTAssertEqual(link?.service, .other)
        XCTAssertEqual(link?.url.absoluteString, "https://whereby.com/acme-standup")
    }

    func testSameURLInTwoFieldsIsStillOne() {
        let link = detect(location: "https://whereby.com/acme", url: "https://whereby.com/acme")
        XCTAssertEqual(link?.service, .other)
    }

    func testMultipleUnknownURLsGiveNoLink() {
        XCTAssertNil(detect(notes: "Agenda https://docs.example.com/a and deck https://slides.example.com/b"))
    }

    func testPlainEventHasNoLink() {
        XCTAssertNil(detect(location: "Conference Room 4B", notes: "Bring laptops."))
        XCTAssertNil(detect())
    }

    func testMailtoAndPhoneAreNotLinks() {
        XCTAssertNil(detect(location: "mailto:nate@example.com", notes: "tel:+15550100"))
    }

    func testTrailingPunctuationIsTrimmed() {
        let link = detect(notes: "Join at https://acme.zoom.us/j/123456789.")
        XCTAssertEqual(link?.url.absoluteString, "https://acme.zoom.us/j/123456789")
    }

    func testCaseInsensitiveHost() {
        XCTAssertEqual(detect(notes: "HTTPS://ACME.ZOOM.US/j/123")?.service, .zoom)
    }

}
