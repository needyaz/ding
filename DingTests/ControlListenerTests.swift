import DingCore
import DingIPC
import XCTest
@testable import Ding

/// The real listener and socket, in the app's sandbox, with a service behind it.
@MainActor
final class ControlListenerTests: XCTestCase {
    private var listener: ControlListener?
    private var path = ""
    private var joined: [DingEvent] = []

    override func setUp() {
        super.setUp()
        path = "\(NSTemporaryDirectory())l\(UUID().uuidString.prefix(8)).sock"
        let start = Date().addingTimeInterval(600)
        let events = [DingEvent(id: "a", title: "Standup", start: start, end: start.addingTimeInterval(1800), calendarTitle: "Work",
                                link: MeetingLink(service: .zoom, url: URL(string: "https://zoom.us/j/1")!))]
        let service = ControlService(environment: .init(
            events: { events },
            access: { .granted },
            permissions: { ControlPermissions(canReadSchedule: true, canOpenMeetings: true) },
            join: { [unowned self] in joined.append($0) }
        ))
        listener = ControlListener(service: service, path: path, requirement: nil)
        listener?.start()
    }

    override func tearDown() {
        listener?.stop()
        listener = nil
        super.tearDown()
    }

    /// Sends a request from a background thread, as the helper would, while the main actor stays free to answer.
    private func send(_ payload: Data) throws -> ControlResponse {
        let path = self.path
        let done = expectation(description: "reply")
        let box = ReplyBox()
        DispatchQueue.global().async {
            box.result = Result { try ControlSocketClient(path: path, timeout: 5).request(payload) }
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        let data = try XCTUnwrap(box.result).get()
        return try JSONDecoder().decode(ControlResponse.self, from: data)
    }

    private func send(_ request: ControlRequest) throws -> ControlResponse {
        try send(JSONEncoder().encode(request))
    }

    func testARequestIsAnsweredThroughTheRealSocket() throws {
        let response = try send(ControlRequest(method: "get_next_meeting"))
        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.result?.objectValue?["meeting"]?.objectValue?["title"]?.stringValue, "Standup")
    }

    func testAJoinRunsOnTheMainActorAndReportsBack() throws {
        let response = try send(ControlRequest(method: "open_meeting"))
        XCTAssertTrue(response.ok)
        XCTAssertEqual(joined.map(\.id), ["a"])
    }

    func testAnUnreadableRequestGetsAnErrorNotSilence() throws {
        let response = try send(Data("this is not a request".utf8))
        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.error?.code, "invalid_request")
    }

    func testAnUnknownMethodIsRefused() throws {
        XCTAssertEqual(try send(ControlRequest(method: "format_disk")).error?.code, "unknown_method")
    }

    func testSeveralRequestsInARow() throws {
        for _ in 0..<5 { XCTAssertTrue(try send(ControlRequest(method: "list_meetings")).ok) }
    }

    func testAfterStoppingNobodyIsListening() throws {
        listener?.stop()
        XCTAssertThrowsError(try ControlSocketClient(path: path, timeout: 1).request(Data("{}".utf8))) {
            XCTAssertEqual($0 as? DingIPCError, .notListening)
        }
    }

    func testAListenerNeedsTheAppGroupInTheBundle() {
        let service = ControlService(environment: .init(events: { [] }, access: { .granted }, permissions: { ControlPermissions() }, join: { _ in }))
        XCTAssertNil(ControlListener(service: service, bundle: Bundle(for: ControlListenerTests.self)),
                     "the test bundle has no DingAppGroup, so there must be no listener (and no socket)")
    }
}

private final class ReplyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Result<Data, Error>?
    var result: Result<Data, Error>? {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}
