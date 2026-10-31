import XCTest
@testable import DingCore

/// Odd inputs: wrappers, lookalike hosts, punctuation, unicode.
final class MeetingLinkDetectorEdgeCaseTests: XCTestCase {
    private func detect(_ source: LinkSource) -> MeetingLink? { MeetingLinkDetector.detect(source) }

    func testEmptyFields() {
        XCTAssertNil(detect(LinkSource(location: "", url: nil, notes: "")))
        XCTAssertNil(detect(LinkSource(location: "   \n  ", notes: "\t")))
    }

    func testConferenceURLIsConsulted() {
        let conf = URL(string: "https://acme.zoom.us/j/999")!
        XCTAssertEqual(detect(LinkSource(conferenceURLs: [conf]))?.service, .zoom)
    }

    func testConferenceURLThatIsUnknownStillFallsBackToOther() {
        let conf = URL(string: "https://whereby.com/room")!
        XCTAssertEqual(detect(LinkSource(conferenceURLs: [conf]))?.service, .other)
    }

    func testFirstKnownLinkWithinAFieldWins() {
        let notes = "Primary https://acme.zoom.us/j/111 backup https://meet.google.com/abc-defg-hij"
        let link = detect(LinkSource(notes: notes))
        XCTAssertEqual(link?.service, .zoom)
        XCTAssertEqual(link?.url.absoluteString, "https://acme.zoom.us/j/111")
    }

    func testMarkdownAndParenthesizedLinks() {
        XCTAssertEqual(detect(LinkSource(notes: "[join](https://acme.zoom.us/j/123)"))?.url.absoluteString, "https://acme.zoom.us/j/123")
        XCTAssertEqual(detect(LinkSource(notes: "(https://meet.google.com/abc-defg-hij)"))?.service, .googleMeet)
    }

    func testAngleBracketAndQuotedLinks() {
        XCTAssertEqual(detect(LinkSource(notes: "<https://acme.zoom.us/j/123>"))?.service, .zoom)
        XCTAssertEqual(detect(LinkSource(notes: #"<a href="https://acme.zoom.us/j/123">join</a>"#))?.service, .zoom)
        XCTAssertEqual(detect(LinkSource(notes: "'https://acme.zoom.us/j/123'"))?.service, .zoom)
    }

    func testHTMLEntityAmpersandsAreDecoded() {
        let link = detect(LinkSource(notes: "https://acme.zoom.us/j/123?pwd=abc&amp;uname=Nate"))
        XCTAssertEqual(link?.url.absoluteString, "https://acme.zoom.us/j/123?pwd=abc&uname=Nate")
    }

    func testGoogleRedirectWithUrlKey() {
        let wrapped = "https://www.google.com/url?url=https%3A%2F%2Facme.webex.com%2Fmeet%2Fnate&sa=D"
        XCTAssertEqual(detect(LinkSource(notes: wrapped))?.service, .webex)
    }

    func testRedirectWithoutInnerURLIsLeftAlone() {
        XCTAssertEqual(detect(LinkSource(notes: "https://www.google.com/url?sa=D"))?.service, .other)
        XCTAssertEqual(detect(LinkSource(notes: "https://www.google.com/url?q=notaurl"))?.service, .other)
    }

    func testRedirectToNonWebSchemeIsNotUnwrapped() {
        let link = detect(LinkSource(notes: "https://www.google.com/url?q=ftp%3A%2F%2Fexample.com%2Ffile"))
        XCTAssertEqual(link?.url.host, "www.google.com")
    }

    func testOrdinaryGoogleLinkIsNotUnwrapped() {
        XCTAssertEqual(detect(LinkSource(notes: "https://www.google.com/maps"))?.url.host, "www.google.com")
    }

    func testSafeLinksWithoutURLParam() {
        XCTAssertEqual(detect(LinkSource(notes: "https://nam06.safelinks.protection.outlook.com/?data=abc"))?.service, .other)
    }

    func testWebexVariants() {
        for url in [
            "https://acme.webex.com/acme/j.php?MTID=abc",
            "https://acme.webex.com/acme/m.php?AT=ml",
            "https://meet1234.webex.com/meet/pr1234567890",
            "https://acme.webex.com/join/nate.eide",
            "https://acme.webex.com/wbxmjs/joinservice/sites/acme/meeting/download/abc",
        ] {
            XCTAssertEqual(detect(LinkSource(location: url))?.service, .webex, url)
        }
    }

    func testZoomVariants() {
        for url in [
            "https://zoom.us/j/123456789",
            "https://us06web.zoom.us/j/123456789?pwd=abc",
            "https://acme.zoom.us/s/123456789",
            "https://acme.zoom.us/w/123456789?tk=abc",
            "https://zoom.us/wc/join/123456789",
            "https://acme.zoomgov.com/j/1600000000",
        ] {
            XCTAssertEqual(detect(LinkSource(location: url))?.service, .zoom, url)
        }
    }

    func testLookalikeHostsAreNotMatched() {
        for url in [
            "https://zoom.us.evil.com/j/123",
            "https://notzoom.us/j/123",
            "https://meet.google.com.evil.com/abc-defg-hij",
            "https://evilteams.microsoft.com.example.org/l/meetup-join/x",
            "https://webex.com.example.org/meet/nate",
        ] {
            XCTAssertEqual(detect(LinkSource(location: url))?.service, .other, url)
        }
    }

    func testNonMeetingPagesOnKnownHostsAreNotMeetings() {
        XCTAssertNotEqual(detect(LinkSource(location: "https://zoom.us/pricing"))?.service, .zoom)
        XCTAssertNotEqual(detect(LinkSource(location: "https://teams.microsoft.com/downloads"))?.service, .teams)
        XCTAssertNotEqual(detect(LinkSource(location: "https://www.webex.com/"))?.service, .webex)
    }

    func testHTTPLinksAreAccepted() {
        XCTAssertEqual(detect(LinkSource(location: "http://acme.zoom.us/j/123"))?.service, .zoom)
    }

    func testSchemelessLinksAreNotDetected() {
        XCTAssertNil(detect(LinkSource(location: "zoom.us/j/123456789")))
    }

    func testZoomDeepLinkIsDetectedAsZoom() {
        XCTAssertEqual(detect(LinkSource(location: "zoommtg://zoom.us/join?confno=123"))?.service, .zoom)
    }

    func testAnyZoomSchemeLinkCountsAsZoom() {
        XCTAssertEqual(detect(LinkSource(location: "zoommtg://example.com/whatever"))?.service, .zoom)
    }

    func testOtherSchemesAreNeverMeetingLinks() {
        XCTAssertNil(detect(LinkSource(location: "ftp://example.com/room", notes: "file:///tmp/x")))
    }

    func testUnicodeAndLongNotes() {
        let filler = String(repeating: "Ünïcode ✓ agenda item. ", count: 2000)
        let link = detect(LinkSource(notes: filler + "https://acme.zoom.us/j/123" + filler))
        XCTAssertEqual(link?.service, .zoom)
    }

    func testPunctuationVariantsAtTheEnd() {
        for tail in [".", ",", ";", ":", "!", "?", ".)", ")."] {
            let link = detect(LinkSource(notes: "(Join https://acme.zoom.us/j/123456789\(tail) thanks"))
            XCTAssertEqual(link?.url.absoluteString, "https://acme.zoom.us/j/123456789", "tail \(tail)")
        }
    }

    func testQueryStringIsPreservedForMeet() {
        XCTAssertEqual(detect(LinkSource(notes: "https://meet.google.com/abc-defg-hij?pli=1&authuser=0"))?.url.query, "pli=1&authuser=0")
    }

    func testMeetLookupLink() {
        XCTAssertEqual(detect(LinkSource(location: "https://meet.google.com/lookup/abc123"))?.service, .googleMeet)
    }

    func testTrailingSlashesDoNotCreateDuplicates() {
        // Different strings, so two "other" candidates: ambiguous by design.
        XCTAssertNil(detect(LinkSource(location: "https://whereby.com/acme", notes: "https://whereby.com/acme/")))
    }
}
