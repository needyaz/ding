import XCTest
@testable import DingCore

/// Deep links into the Zoom and Teams desktop apps.
final class NativeLinksTests: XCTestCase {
    func testZoomNativeURL() {
        let web = URL(string: "https://us02web.zoom.us/j/84512345678?pwd=abc123")!
        XCTAssertEqual(NativeLinks.zoom(from: web)?.absoluteString, "zoommtg://us02web.zoom.us/join?confno=84512345678&pwd=abc123")
    }

    func testZoomNativeURLNilForPersonalRoom() {
        XCTAssertNil(NativeLinks.zoom(from: URL(string: "https://acme.zoom.us/my/nate")!))
    }

    func testTeamsNativeURL() {
        let web = URL(string: "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc/0?context=x")!
        XCTAssertEqual(NativeLinks.teams(from: web)?.scheme, "msteams")
        XCTAssertEqual(NativeLinks.teams(from: web)?.host, "teams.microsoft.com")
        XCTAssertEqual(NativeLinks.teams(from: web)?.path, web.path)
    }


    func testZoomNativePassesThroughDeepLink() {
        let deep = URL(string: "zoommtg://zoom.us/join?confno=1")!
        XCTAssertEqual(NativeLinks.zoom(from: deep), deep)
    }

    func testZoomNativeKeepsAllQueryItems() {
        let web = URL(string: "https://acme.zoom.us/j/123?pwd=abc&uname=Nate")!
        let native = NativeLinks.zoom(from: web)
        XCTAssertEqual(native?.host, "acme.zoom.us")
        XCTAssertEqual(native?.path, "/join")
        let items = URLComponents(url: native!, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(items?.map(\.name), ["confno", "pwd", "uname"])
        XCTAssertEqual(items?.map(\.value), ["123", "abc", "Nate"])
    }

    func testZoomNativeWithoutQuery() {
        XCTAssertEqual(NativeLinks.zoom(from: URL(string: "https://zoom.us/j/123")!)?.absoluteString, "zoommtg://zoom.us/join?confno=123")
    }

    func testZoomNativeRejectsNonJoinPaths() {
        XCTAssertNil(NativeLinks.zoom(from: URL(string: "https://zoom.us/j")!))
        XCTAssertNil(NativeLinks.zoom(from: URL(string: "https://zoom.us/s/123")!))
        XCTAssertNil(NativeLinks.zoom(from: URL(string: "https://zoom.us/")!))
    }

    func testTeamsNativeRejectsNonWebSchemes() {
        XCTAssertNil(NativeLinks.teams(from: URL(string: "msteams://teams.microsoft.com/l/meetup-join/x")!))
        XCTAssertNil(NativeLinks.teams(from: URL(string: "ftp://example.com/x")!))
    }

    func testTeamsNativePreservesQuery() {
        let web = URL(string: "https://teams.microsoft.com/l/meetup-join/abc/0?context=%7B%22Tid%22%7D")!
        XCTAssertEqual(NativeLinks.teams(from: web)?.absoluteString, "msteams://teams.microsoft.com/l/meetup-join/abc/0?context=%7B%22Tid%22%7D")
    }
}
