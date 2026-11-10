import DingIPC
import Foundation
import XCTest
@testable import DingMCP

/// The open_meeting description must name the reply field the app actually sends.
final class OpenMeetingDescriptionTests: MCPTestCase {
    private func openMeetingDescription() throws -> String {
        let reply = try send(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)
        let tools = try XCTUnwrap((reply?["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        let tool = try XCTUnwrap(tools.first { $0["name"] as? String == "open_meeting" })
        return try XCTUnwrap(tool["description"] as? String)
    }

    /// Field names the description presents as `name: true`.
    private func fieldsNamedAsTrue(in text: String) throws -> [String] {
        let regex = try NSRegularExpression(pattern: "([A-Za-z_]+): true")
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    func test_DING_MCP_019_theOpenMeetingDescriptionNamesOnlyFieldsTheReplyCarries() throws {
        // What the app answers when a meeting was opened and the schedule is not visible.
        backend.response = .success(.object(["opened": .bool(true)]))
        let result = try call("open_meeting")
        let replyFields = Set(try XCTUnwrap(result["structuredContent"] as? [String: Any]).keys)

        let named = try fieldsNamedAsTrue(in: try openMeetingDescription())
        XCTAssertFalse(named.isEmpty, "DING-MCP-019: the description says how the reply confirms the meeting was opened")
        for field in named {
            XCTAssertTrue(replyFields.contains(field), "DING-MCP-019: the description names \(field), which the reply does not carry")
        }
    }
}
