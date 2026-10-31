import Foundation

/// A JSON value, for request parameters and results that pass through without the transport knowing their shape.
public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Int.self) { self = .int(value) }
        else if let value = try? container.decode(Double.self) { self = .double(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    public var stringValue: String? { if case .string(let value) = self { value } else { nil } }
    public var boolValue: Bool? { if case .bool(let value) = self { value } else { nil } }
    /// An integer, also accepting a whole-number double (some JSON encoders write 3 as 3.0).
    public var intValue: Int? {
        switch self {
        case .int(let value): value
        case .double(let value) where value == value.rounded() && abs(value) < 1e15: Int(value)
        default: nil
        }
    }
    public var objectValue: [String: JSONValue]? { if case .object(let value) = self { value } else { nil } }
}

/// The operations the app offers its helper. These are also the MCP tool names.
public enum ControlMethod: String, CaseIterable, Codable, Sendable {
    case getNextMeeting = "get_next_meeting"
    case listMeetings = "list_meetings"
    case openMeeting = "open_meeting"
}

public struct ControlRequest: Codable, Equatable, Sendable {
    public var method: String
    public var params: [String: JSONValue]

    public init(method: String, params: [String: JSONValue] = [:]) {
        self.method = method
        self.params = params
    }
}

public struct ControlError: Codable, Equatable, Sendable {
    public var code: String
    public var message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public struct ControlResponse: Codable, Equatable, Sendable {
    public var ok: Bool
    public var result: JSONValue?
    public var error: ControlError?

    public init(ok: Bool, result: JSONValue?, error: ControlError?) {
        self.ok = ok
        self.result = result
        self.error = error
    }

    public static func success(_ result: JSONValue) -> ControlResponse { ControlResponse(ok: true, result: result, error: nil) }
    public static func failure(code: String, message: String) -> ControlResponse {
        ControlResponse(ok: false, result: nil, error: ControlError(code: code, message: message))
    }
}
