import XCTest
@testable import DingIPC

final class JSONValueTests: XCTestCase {
    private func roundTrip(_ value: JSONValue) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    }

    func testEveryKindRoundTrips() throws {
        let values: [JSONValue] = [
            .null, .bool(true), .bool(false), .int(0), .int(-7), .int(Int.max), .double(1.5), .string(""), .string("héllo ✓"),
            .array([]), .array([.int(1), .string("a"), .null]), .object([:]),
            .object(["a": .object(["b": .array([.bool(true), .double(2.5)])])]),
        ]
        for value in values { XCTAssertEqual(try roundTrip(value), value, "\(value)") }
    }

    func testDecodesRealJSON() throws {
        let json = #"{"days": 3, "include_all_day": true, "id": "abc", "ratio": 0.5, "none": null, "list": [1, 2]}"#
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        let object = try XCTUnwrap(value.objectValue)
        XCTAssertEqual(object["days"]?.intValue, 3)
        XCTAssertEqual(object["include_all_day"]?.boolValue, true)
        XCTAssertEqual(object["id"]?.stringValue, "abc")
        XCTAssertEqual(object["ratio"], .double(0.5))
        XCTAssertEqual(object["none"], .null)
        XCTAssertEqual(object["list"], .array([.int(1), .int(2)]))
    }

    func testAccessorsReturnNilForTheWrongKind() {
        XCTAssertNil(JSONValue.string("1").intValue)
        XCTAssertNil(JSONValue.int(1).stringValue)
        XCTAssertNil(JSONValue.int(1).boolValue)
        XCTAssertNil(JSONValue.null.objectValue)
        XCTAssertNil(JSONValue.double(1.5).intValue)
    }

    func testWholeDoublesCountAsIntegers() {
        XCTAssertEqual(JSONValue.double(3.0).intValue, 3)
        XCTAssertNil(JSONValue.double(3.5).intValue)
        XCTAssertNil(JSONValue.double(1e20).intValue)
    }

    func testBoolIsNotConfusedWithNumbers() throws {
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: Data("true".utf8)), .bool(true))
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: Data("1".utf8)), .int(1))
    }
}

final class ControlMessageTests: XCTestCase {
    func testMethodNamesAreTheToolNames() {
        XCTAssertEqual(ControlMethod.allCases.map(\.rawValue), ["get_next_meeting", "list_meetings", "open_meeting"])
        XCTAssertEqual(ControlMethod(rawValue: "open_meeting"), .openMeeting)
        XCTAssertNil(ControlMethod(rawValue: "delete_everything"))
    }

    func testRequestRoundTripsAndParamsDefaultToEmpty() throws {
        let request = ControlRequest(method: "list_meetings", params: ["days": .int(3)])
        XCTAssertEqual(try JSONDecoder().decode(ControlRequest.self, from: JSONEncoder().encode(request)), request)
        XCTAssertEqual(ControlRequest(method: "get_next_meeting").params, [:])
    }

    func testResponseConstructors() throws {
        let ok = ControlResponse.success(.object(["meeting": .null]))
        XCTAssertTrue(ok.ok)
        XCTAssertNil(ok.error)
        let bad = ControlResponse.failure(code: "opening_off", message: "no")
        XCTAssertFalse(bad.ok)
        XCTAssertEqual(bad.error, ControlError(code: "opening_off", message: "no"))
        XCTAssertNil(bad.result)
        for response in [ok, bad] {
            XCTAssertEqual(try JSONDecoder().decode(ControlResponse.self, from: JSONEncoder().encode(response)), response)
        }
    }
}

final class DingIPCRulesTests: XCTestCase {
    func testTeamIDIsThePrefixOfTheAppGroup() {
        XCTAssertEqual(DingIPC.teamID(fromAppGroup: "46XLY7Y9P8.blue.luci.Ding"), "46XLY7Y9P8")
        XCTAssertEqual(DingIPC.teamID(fromAppGroup: "ABCDE12345.x"), "ABCDE12345")
        XCTAssertNil(DingIPC.teamID(fromAppGroup: ""))
        XCTAssertNil(DingIPC.teamID(fromAppGroup: ".blue.luci"))
    }

    func testRequirementPinsTheTeamAndTheHelper() {
        let requirement = DingIPC.codeSigningRequirement(teamID: "46XLY7Y9P8")
        XCTAssertTrue(requirement.contains("anchor apple generic"))
        XCTAssertTrue(requirement.contains(#"certificate leaf[subject.OU] = "46XLY7Y9P8""#))
        XCTAssertTrue(requirement.contains(#"identifier "blue.luci.Ding.mcp""#), "a sibling app of the same team is not let in")
    }

    func testSocketPathIsShortEnoughForAUnixSocket() throws {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/46XLY7Y9P8.blue.luci.Ding/c.sock")
        XCTAssertLessThan(url.path.utf8.count, 104, "sockaddr_un.sun_path holds about 104 bytes")
        XCTAssertEqual(url.lastPathComponent, "c.sock")
    }

    func testTheSocketLivesInTheNamedGroupContainer() throws {
        let url = try XCTUnwrap(DingIPC.socketURL(appGroup: "46XLY7Y9P8.blue.luci.Ding"))
        XCTAssertTrue(url.path.contains("Group Containers/46XLY7Y9P8.blue.luci.Ding/"))
        XCTAssertEqual(url.lastPathComponent, "c.sock")
    }
}
