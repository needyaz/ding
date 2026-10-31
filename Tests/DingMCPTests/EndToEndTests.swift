import Darwin
import DingIPC
import XCTest
@testable import DingMCP

/// The MCP server talking to a stand-in for the app over a real Unix socket.
final class EndToEndTests: XCTestCase {
    private var servers: [ControlSocketServer] = []

    override func tearDown() {
        servers.forEach { $0.stop() }
        servers.removeAll()
        super.tearDown()
    }

    private func tempSocketPath() -> String { "\(NSTemporaryDirectory())e\(UUID().uuidString.prefix(8)).sock" }

    /// Starts a fake app whose handler decodes the request and answers with `respond`.
    private func startFakeApp(
        requirement: String? = nil,
        respond: @escaping @Sendable (ControlRequest) -> Data
    ) throws -> String {
        let path = tempSocketPath()
        let server = ControlSocketServer(path: path, requirement: requirement) { data in
            guard let request = try? JSONDecoder().decode(ControlRequest.self, from: data) else { return Data("not a request".utf8) }
            return respond(request)
        }
        try server.start()
        servers.append(server)
        return path
    }

    private func json(_ response: ControlResponse) -> Data { try! JSONEncoder().encode(response) }

    private func runTool(_ tool: String, arguments: String = "{}", path: String, timeout: TimeInterval = 3) throws -> [String: Any] {
        let server = MCPServer(backend: SocketBackend(path: path, timeout: timeout), version: "1")
        let message = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"\#(tool)","arguments":\#(arguments)}}"#
        let done = DispatchSemaphore(value: 0)
        let box = Box<Data?>()
        Task { box.value = await server.handle(Data(message.utf8)); done.signal() }
        done.wait()
        let data = try XCTUnwrap(box.value ?? nil)
        let reply = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(reply["result"] as? [String: Any])
    }

    private func text(_ result: [String: Any]) throws -> String {
        try XCTUnwrap(((result["content"] as? [[String: Any]])?.first)?["text"] as? String)
    }

    // MARK: Happy path

    func testAToolCallReachesTheAppAndTheAnswerComesBack() throws {
        let seen = Box<ControlRequest>()
        let path = try startFakeApp { request in
            seen.value = request
            return self.json(.success(.object(["meeting": .object(["title": .string("Standup")])])))
        }
        let result = try runTool("get_next_meeting", path: path)
        XCTAssertEqual(seen.value, ControlRequest(method: "get_next_meeting"))
        XCTAssertEqual(result["isError"] as? Bool, false)
        XCTAssertTrue(try text(result).contains("Standup"))
    }

    func testArgumentsTravelAllTheWay() throws {
        let seen = Box<ControlRequest>()
        let path = try startFakeApp { request in seen.value = request; return self.json(.success(.object([:]))) }
        _ = try runTool("list_meetings", arguments: #"{"days":4,"include_all_day":true}"#, path: path)
        XCTAssertEqual(seen.value?.params, ["days": .int(4), "include_all_day": .bool(true)])
    }

    func testAFailureFromTheAppReachesTheModelWithItsMessage() throws {
        let path = try startFakeApp { _ in self.json(.failure(code: "opening_off", message: "The user hasn't allowed AI assistants to open meetings.")) }
        let result = try runTool("open_meeting", path: path)
        XCTAssertEqual(result["isError"] as? Bool, true)
        XCTAssertEqual(try text(result), "The user hasn't allowed AI assistants to open meetings.")
    }

    func testSeveralCallsInARowEachGetTheirOwnAnswer() throws {
        let counter = Box<Int>()
        counter.value = 0
        let path = try startFakeApp { _ in
            counter.value = (counter.value ?? 0) + 1
            return self.json(.success(.object(["n": .int(counter.value ?? 0)])))
        }
        for expected in 1...5 {
            XCTAssertTrue(try text(try runTool("get_next_meeting", path: path)).contains("\"n\" : \(expected)"))
        }
    }

    // MARK: Things going wrong

    func testDingNotRunning() throws {
        let result = try runTool("get_next_meeting", path: tempSocketPath())
        XCTAssertEqual(result["isError"] as? Bool, true)
        XCTAssertTrue(try text(result).contains("Ding isn't running"))
    }

    func testDingHangingTimesOut() throws {
        let path = try startFakeApp { _ in
            Thread.sleep(forTimeInterval: 2)
            return self.json(.success(.null))
        }
        let result = try runTool("get_next_meeting", path: path, timeout: 0.3)
        XCTAssertEqual(result["isError"] as? Bool, true)
        XCTAssertTrue(try text(result).contains("in time"))
    }

    func testDingRefusingThisProgramIsExplained() throws {
        let path = try startFakeApp(requirement: #"identifier "no.such.identifier""#) { _ in self.json(.success(.null)) }
        let result = try runTool("get_next_meeting", path: path)
        XCTAssertEqual(result["isError"] as? Bool, true)
        XCTAssertTrue(try text(result).contains("closed the connection"))
    }

    func testAGarbledReplyIsReportedNotCrashed() throws {
        let path = try startFakeApp { _ in Data("this is not json".utf8) }
        let result = try runTool("get_next_meeting", path: path)
        XCTAssertEqual(result["isError"] as? Bool, true)
        XCTAssertTrue(try text(result).contains("couldn't read"))
    }

    func testAnEmptyReplyIsReportedNotCrashed() throws {
        let path = try startFakeApp { _ in Data() }
        XCTAssertEqual(try runTool("get_next_meeting", path: path)["isError"] as? Bool, true)
    }

    func testTheServerSurvivesTheAppGoingAwayBetweenCalls() throws {
        let path = tempSocketPath()
        let server = ControlSocketServer(path: path, requirement: nil) { _ in self.json(.success(.object([:]))) }
        try server.start()
        XCTAssertEqual(try runTool("get_next_meeting", path: path)["isError"] as? Bool, false)
        server.stop()
        XCTAssertTrue(try text(try runTool("get_next_meeting", path: path)).contains("isn't running"))
    }
}

final class ServeLoopTests: XCTestCase {
    private func run(_ lines: [String], backend: ControlBackend = FakeBackend()) async -> [String] {
        let server = MCPServer(backend: backend, version: "1")
        let output = Box<[String]>()
        output.value = []
        let stream = AsyncStream<String> { continuation in
            lines.forEach { continuation.yield($0) }
            continuation.finish()
        }
        await server.serve(lines: stream) { data in output.value?.append(String(decoding: data, as: UTF8.self)) }
        return output.value ?? []
    }

    func testEachReplyIsOneLineEndingInANewline() async throws {
        let out = await run([#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#, #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#])
        XCTAssertEqual(out.count, 2)
        for reply in out {
            XCTAssertTrue(reply.hasSuffix("\n"))
            XCTAssertEqual(reply.filter { $0 == "\n" }.count, 1)
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(reply.utf8)))
        }
    }

    func testRepliesComeBackInTheOrderOfTheRequests() async throws {
        let out = await run((1...5).map { #"{"jsonrpc":"2.0","id":\#($0),"method":"ping"}"# })
        let ids = out.compactMap { (try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])?["id"] as? Int }
        XCTAssertEqual(ids, [1, 2, 3, 4, 5])
    }

    func testNotificationsAndBlankLinesProduceNoOutput() async throws {
        let out = await run(["", "   ", #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#, "\t"])
        XCTAssertTrue(out.isEmpty)
    }

    func testABadLineDoesNotStopTheLoop() async throws {
        let out = await run(["{ broken", #"{"jsonrpc":"2.0","id":1,"method":"ping"}"#])
        XCTAssertEqual(out.count, 2)
        XCTAssertTrue(out[0].contains("-32700"))
        XCTAssertTrue(out[1].contains(#""id":1"#))
    }

    func testTheLoopEndsWhenTheInputEnds() async throws {
        let out = await run([])
        XCTAssertTrue(out.isEmpty)
    }

    func testLinesWithSurroundingWhitespaceAreAccepted() async throws {
        let out = await run(["  " + #"{"jsonrpc":"2.0","id":1,"method":"ping"}"# + "  "])
        XCTAssertEqual(out.count, 1)
    }

    func testAWindowsLineEndingIsAccepted() async throws {
        let out = await run([#"{"jsonrpc":"2.0","id":1,"method":"ping"}"# + "\r"])
        XCTAssertEqual(out.count, 1)
    }
}

final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T?
    var value: T? {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}
