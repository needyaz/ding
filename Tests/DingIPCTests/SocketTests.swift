import Darwin
import Security
import XCTest
@testable import DingIPC

final class FramingTests: XCTestCase {
    private func socketPair() throws -> (Int32, Int32) {
        var fds: [Int32] = [0, 0]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds), 0)
        return (fds[0], fds[1])
    }

    func testFramesRoundTrip() throws {
        let (a, b) = try socketPair()
        defer { close(a); close(b) }
        for payload in [Data("hello".utf8), Data()] {
            try Framing.write(payload, to: a)
            XCTAssertEqual(try Framing.read(from: b), payload)
        }
    }

    func testALargeFrameSurvivesThePartialReadsAndWritesOfARealSocket() throws {
        let (a, b) = try socketPair()
        defer { close(a); close(b) }
        let payload = Data((0..<500_000).map { UInt8($0 % 251) })
        // Bigger than the socket buffer, so the write can't finish until someone reads.
        let writer = Thread { try? Framing.write(payload, to: a) }
        writer.start()
        XCTAssertEqual(try Framing.read(from: b), payload)
    }

    func testSeveralFramesInARowKeepTheirBoundaries() throws {
        let (a, b) = try socketPair()
        defer { close(a); close(b) }
        try Framing.write(Data("one".utf8), to: a)
        try Framing.write(Data("two".utf8), to: a)
        XCTAssertEqual(try Framing.read(from: b), Data("one".utf8))
        XCTAssertEqual(try Framing.read(from: b), Data("two".utf8))
    }

    func testCleanCloseBetweenFramesReadsAsNil() throws {
        let (a, b) = try socketPair()
        defer { close(b) }
        close(a)
        XCTAssertNil(try Framing.read(from: b))
    }

    func testCloseInTheMiddleOfAFrameIsAnError() throws {
        let (a, b) = try socketPair()
        defer { close(b) }
        var length = UInt32(10).bigEndian
        _ = withUnsafeBytes(of: &length) { Darwin.write(a, $0.baseAddress, 4) }
        _ = Darwin.write(a, "abc", 3)
        close(a)
        XCTAssertThrowsError(try Framing.read(from: b)) { XCTAssertEqual($0 as? DingIPCError, .closed) }
    }

    func testAHugeAnnouncedLengthIsRefusedBeforeAnythingIsAllocated() throws {
        let (a, b) = try socketPair()
        defer { close(a); close(b) }
        var length = UInt32.max.bigEndian
        _ = withUnsafeBytes(of: &length) { Darwin.write(a, $0.baseAddress, 4) }
        XCTAssertThrowsError(try Framing.read(from: b)) { XCTAssertEqual($0 as? DingIPCError, .frameTooLarge) }
    }

    func testWritingAnOversizedFrameIsRefused() throws {
        let (a, b) = try socketPair()
        defer { close(a); close(b) }
        XCTAssertThrowsError(try Framing.write(Data(count: Framing.maxFrameSize + 1), to: a)) {
            XCTAssertEqual($0 as? DingIPCError, .frameTooLarge)
        }
        XCTAssertNoThrow(try Framing.write(Data(count: 1000), to: a))
    }

    func testAReadTimesOutInsteadOfHanging() throws {
        let (a, b) = try socketPair()
        defer { close(a); close(b) }
        var tv = timeval(tv_sec: 0, tv_usec: 100_000)
        setsockopt(b, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        XCTAssertThrowsError(try Framing.read(from: b)) { XCTAssertEqual($0 as? DingIPCError, .timedOut) }
    }
}

final class ControlSocketTests: XCTestCase {
    private var servers: [ControlSocketServer] = []

    override func tearDown() {
        servers.forEach { $0.stop() }
        servers.removeAll()
        super.tearDown()
    }

    private func tempSocketPath() -> String {
        "\(NSTemporaryDirectory())d\(UUID().uuidString.prefix(8)).sock"
    }

    @discardableResult
    private func startServer(path: String, requirement: String? = nil, handler: @escaping ControlSocketServer.Handler) throws -> ControlSocketServer {
        let server = ControlSocketServer(path: path, requirement: requirement, handler: handler)
        try server.start()
        servers.append(server)
        return server
    }

    /// A requirement the test process itself satisfies.
    private func ownRequirement() throws -> String {
        var code: SecCode?
        XCTAssertEqual(SecCodeCopySelf([], &code), errSecSuccess)
        var staticCode: SecStaticCode?
        XCTAssertEqual(SecCodeCopyStaticCode(try XCTUnwrap(code), [], &staticCode), errSecSuccess)
        var requirement: SecRequirement?
        XCTAssertEqual(SecCodeCopyDesignatedRequirement(try XCTUnwrap(staticCode), [], &requirement), errSecSuccess)
        var text: CFString?
        XCTAssertEqual(SecRequirementCopyString(try XCTUnwrap(requirement), [], &text), errSecSuccess)
        return try XCTUnwrap(text) as String
    }

    func testARequestGetsItsResponse() throws {
        let path = tempSocketPath()
        try startServer(path: path) { Data("echo:".utf8) + $0 }
        XCTAssertEqual(try ControlSocketClient(path: path, timeout: 3).request(Data("hi".utf8)), Data("echo:hi".utf8))
    }

    func testManyRequestsInSequence() throws {
        let path = tempSocketPath()
        try startServer(path: path) { $0 }
        let client = ControlSocketClient(path: path, timeout: 3)
        for i in 0..<25 { XCTAssertEqual(try client.request(Data("\(i)".utf8)), Data("\(i)".utf8)) }
    }

    func testConcurrentClientsAreAllAnswered() throws {
        let path = tempSocketPath()
        try startServer(path: path) { request in
            try? await Task.sleep(nanoseconds: 30_000_000)
            return request
        }
        let done = expectation(description: "all answered")
        done.expectedFulfillmentCount = 8
        let results = LockedList<Bool>()
        for i in 0..<8 {
            DispatchQueue.global().async {
                let reply = try? ControlSocketClient(path: path, timeout: 5).request(Data("c\(i)".utf8))
                results.append(reply == Data("c\(i)".utf8))
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 10)
        XCTAssertEqual(results.values, Array(repeating: true, count: 8))
    }

    func testAnAsyncHandlerIsAwaited() throws {
        let path = tempSocketPath()
        try startServer(path: path) { request in
            try? await Task.sleep(nanoseconds: 100_000_000)
            return Data("late:".utf8) + request
        }
        XCTAssertEqual(try ControlSocketClient(path: path, timeout: 3).request(Data("x".utf8)), Data("late:x".utf8))
    }

    func testTheSocketIsOwnerOnly() throws {
        let path = tempSocketPath()
        try startServer(path: path) { $0 }
        var info = stat()
        XCTAssertEqual(stat(path, &info), 0)
        XCTAssertEqual(info.st_mode & 0o777, 0o600)
    }

    func testAPeerThatSatisfiesTheRequirementIsServed() throws {
        let path = tempSocketPath()
        try startServer(path: path, requirement: try ownRequirement()) { $0 }
        XCTAssertEqual(try ControlSocketClient(path: path, timeout: 3).request(Data("ok".utf8)), Data("ok".utf8))
    }

    func testAPeerThatFailsTheRequirementGetsNothing() throws {
        let path = tempSocketPath()
        let calls = LockedList<Int>()
        try startServer(path: path, requirement: #"identifier "no.such.identifier""#) { request in
            calls.append(1)
            return request
        }
        XCTAssertThrowsError(try ControlSocketClient(path: path, timeout: 2).request(Data("secret".utf8))) { error in
            XCTAssertTrue([.closed, .timedOut].contains(error as? DingIPCError) || (error as? DingIPCError).map { if case .socket = $0 { true } else { false } } == true, "\(error)")
        }
        XCTAssertTrue(calls.values.isEmpty, "the handler must never run for an unverified peer")
    }

    func testAMalformedRequirementRefusesEveryone() throws {
        let path = tempSocketPath()
        let calls = LockedList<Int>()
        try startServer(path: path, requirement: "this is not a requirement") { calls.append(1); return $0 }
        XCTAssertThrowsError(try ControlSocketClient(path: path, timeout: 2).request(Data("x".utf8)))
        XCTAssertTrue(calls.values.isEmpty)
    }

    func testStoppingRemovesTheSocketAndRefusesConnections() throws {
        let path = tempSocketPath()
        let server = try startServer(path: path) { $0 }
        server.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        XCTAssertThrowsError(try ControlSocketClient(path: path, timeout: 1).request(Data()))
    }

    func testAStaleSocketFileFromACrashIsReplaced() throws {
        let path = tempSocketPath()
        FileManager.default.createFile(atPath: path, contents: Data("stale".utf8))
        try startServer(path: path) { _ in Data("fresh".utf8) }
        XCTAssertEqual(try ControlSocketClient(path: path, timeout: 3).request(Data()), Data("fresh".utf8))
    }

    func testAServerThatNeverRepliesTimesOutTheClient() throws {
        let path = tempSocketPath()
        // A raw listener that accepts and says nothing.
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = try ControlSocketServer.address(for: path)
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        XCTAssertEqual(bound, 0)
        XCTAssertEqual(listen(fd, 1), 0)
        defer { close(fd); unlink(path) }
        XCTAssertThrowsError(try ControlSocketClient(path: path, timeout: 0.4).request(Data("x".utf8))) {
            XCTAssertEqual($0 as? DingIPCError, .timedOut)
        }
    }

    func testNothingListeningIsAClearError() {
        XCTAssertThrowsError(try ControlSocketClient(path: tempSocketPath(), timeout: 1).request(Data())) {
            XCTAssertEqual($0 as? DingIPCError, .notListening)
        }
    }

    func testAStaleSocketFileNobodyListensOnIsTheSameAsNotRunning() throws {
        // What a crashed server leaves behind: a socket file with no process behind it.
        let path = tempSocketPath()
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = try ControlSocketServer.address(for: path)
        _ = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        close(fd)
        defer { unlink(path) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        XCTAssertThrowsError(try ControlSocketClient(path: path, timeout: 1).request(Data())) {
            XCTAssertEqual($0 as? DingIPCError, .notListening)
        }
    }

    func testAShortTimeoutDoesNotBecomeNoTimeout() throws {
        // A zero timeval means "wait forever"; 0.05s must still time out.
        let path = tempSocketPath()
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = try ControlSocketServer.address(for: path)
        _ = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        listen(fd, 1)
        defer { close(fd); unlink(path) }
        let started = Date()
        XCTAssertThrowsError(try ControlSocketClient(path: path, timeout: 0.05).request(Data("x".utf8))) {
            XCTAssertEqual($0 as? DingIPCError, .timedOut)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }

    func testAnOversizedRequestDropsTheConnection() throws {
        let path = tempSocketPath()
        try startServer(path: path) { $0 }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(fd) }
        var address = try ControlSocketServer.address(for: path)
        _ = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        var length = UInt32.max.bigEndian
        _ = withUnsafeBytes(of: &length) { Darwin.write(fd, $0.baseAddress, 4) }
        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        XCTAssertNil(try Framing.read(from: fd), "the server should hang up without replying")
    }

    func testAPathThatIsTooLongIsRejected() {
        let path = "/tmp/" + String(repeating: "a", count: 200)
        let server = ControlSocketServer(path: path, requirement: nil) { $0 }
        XCTAssertThrowsError(try server.start()) { error in
            guard case .socket(let detail)? = error as? DingIPCError else { return XCTFail("\(error)") }
            XCTAssertTrue(detail.contains("too long"), detail)
        }
    }
}

private final class LockedList<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [T] = []
    func append(_ value: T) { lock.lock(); storage.append(value); lock.unlock() }
    var values: [T] { lock.lock(); defer { lock.unlock() }; return storage }
}
