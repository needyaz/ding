import Foundation
import XCTest
@testable import DingMCP

/// Lines from MCP clients may carry surrounding spaces, tabs or a Windows line ending; the message inside still counts.
final class ServeLineTrimmingTests: XCTestCase {
    private func serve(_ lines: [String]) async -> [String] {
        let server = MCPServer(backend: FakeBackend(), version: "1")
        let output = Box<[String]>()
        output.value = []
        let stream = AsyncStream<String> { continuation in
            lines.forEach { continuation.yield($0) }
            continuation.finish()
        }
        await server.serve(lines: stream) { data in output.value?.append(String(decoding: data, as: UTF8.self)) }
        return output.value ?? []
    }

    private func object(_ reply: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any])
    }

    private let ping = #"{"jsonrpc":"2.0","id":1,"method":"ping"}"#
    private let toolsList = #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#

    private func assertSameSuccessfulReply(padded: String, clean: String, _ what: String) async throws {
        let expected = await serve([clean])
        let actual = await serve([padded])
        XCTAssertEqual(expected.count, 1, "DING-MCP-003: the clean line gets one reply")
        XCTAssertEqual(actual.count, 1, "DING-MCP-003: \(what) gets one reply")
        guard let reply = actual.first, let reference = expected.first else { return }
        XCTAssertFalse(reply.contains("-32700"), "DING-MCP-003: \(what) is not a parse error")
        let replyObject = try object(reply)
        XCTAssertNil(replyObject["error"], "DING-MCP-003: \(what) gets no error")
        XCTAssertNotNil(replyObject["result"], "DING-MCP-003: \(what) gets a result")
        XCTAssertEqual(replyObject["id"] as? Int, try object(reference)["id"] as? Int, "DING-MCP-003: \(what) answers the same request")
        XCTAssertEqual(
            replyObject as NSDictionary, try object(reference) as NSDictionary,
            "DING-MCP-003: \(what) gets the same reply as the trimmed line"
        )
    }

    func test_DING_MCP_003_keeps_surroundingSpacesAreTrimmed() async throws {
        try await assertSameSuccessfulReply(padded: "   " + ping + "  ", clean: ping, "a line with surrounding spaces")
    }

    func test_DING_MCP_003_keeps_surroundingTabsAreTrimmed() async throws {
        try await assertSameSuccessfulReply(padded: "\t" + toolsList + "\t\t", clean: toolsList, "a line with surrounding tabs")
    }

    func test_DING_MCP_003_keeps_aTrailingCarriageReturnIsTrimmed() async throws {
        try await assertSameSuccessfulReply(padded: ping + "\r", clean: ping, "a line ending in a carriage return")
    }
}
