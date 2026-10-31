import DingIPC
import Foundation

/// How the MCP server reaches Ding.
public protocol ControlBackend: Sendable {
    func send(_ request: ControlRequest) async throws -> ControlResponse
}

public enum BackendError: Error, Equatable {
    /// Nothing is listening: Ding isn't running.
    case dingNotRunning
    case other(String)
}

/// A Model Context Protocol server over newline-delimited JSON-RPC 2.0 (the stdio transport). It holds no state
/// between messages, so each message can be handled on its own: `handle` takes one line and returns the reply, if any.
public struct MCPServer: Sendable {
    /// Newest first. A client that asks for one of these gets it; anything else gets the newest.
    public static let supportedProtocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    private let backend: ControlBackend
    private let version: String

    public init(backend: ControlBackend, version: String) {
        self.backend = backend
        self.version = version
    }

    /// Handles one JSON-RPC message (or a batch) and returns the bytes to write back, or nil if no reply is due.
    public func handle(_ message: Data) async -> Data? {
        let parsed: Any
        do { parsed = try JSONSerialization.jsonObject(with: message, options: [.fragmentsAllowed]) }
        catch { return encode(errorResponse(id: NSNull(), code: -32700, message: "Parse error")) }

        if let batch = parsed as? [Any] {
            guard !batch.isEmpty else { return encode(errorResponse(id: NSNull(), code: -32600, message: "Invalid Request: empty batch")) }
            var replies: [[String: Any]] = []
            for item in batch { if let reply = await handleObject(item) { replies.append(reply) } }
            return replies.isEmpty ? nil : encode(replies)
        }
        return await handleObject(parsed).flatMap { encode($0) }
    }

    // MARK: Dispatch

    private func handleObject(_ value: Any) async -> [String: Any]? {
        guard let object = value as? [String: Any] else {
            return errorResponse(id: NSNull(), code: -32600, message: "Invalid Request")
        }
        // Responses to requests we never make: nothing to do.
        if object["method"] == nil, object["result"] != nil || object["error"] != nil { return nil }

        let id = object["id"]
        guard object["jsonrpc"] as? String == "2.0", let method = object["method"] as? String else {
            return errorResponse(id: id ?? NSNull(), code: -32600, message: "Invalid Request")
        }
        // A message without an id is a notification and never gets a reply.
        guard let id, !(id is NSNull) else { return nil }
        let params = object["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize": return result(id: id, initializeResult(params))
        case "ping": return result(id: id, [:])
        case "tools/list": return result(id: id, ["tools": Tools.definitions])
        case "tools/call": return await callTool(id: id, params: params)
        default: return errorResponse(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    private func initializeResult(_ params: [String: Any]) -> [String: Any] {
        let requested = params["protocolVersion"] as? String
        let negotiated = requested.flatMap { Self.supportedProtocolVersions.contains($0) ? $0 : nil } ?? Self.supportedProtocolVersions[0]
        return [
            "protocolVersion": negotiated,
            "capabilities": ["tools": ["listChanged": false]],
            "serverInfo": ["name": "ding", "title": "Ding", "version": version],
            "instructions": Tools.instructions,
        ]
    }

    // MARK: tools/call

    private func callTool(id: Any, params: [String: Any]) async -> [String: Any] {
        guard let name = params["name"] as? String else {
            return errorResponse(id: id, code: -32602, message: "Invalid params: a tool name is required")
        }
        guard let method = ControlMethod(rawValue: name) else {
            return errorResponse(id: id, code: -32602, message: "Unknown tool: \(name)")
        }
        let rawArguments = params["arguments"]
        guard rawArguments == nil || rawArguments is NSNull || rawArguments is [String: Any] else {
            return errorResponse(id: id, code: -32602, message: "Invalid params: arguments must be an object")
        }
        let arguments = rawArguments as? [String: Any] ?? [:]

        let parameters: [String: JSONValue]
        do { parameters = try Tools.parameters(for: method, arguments: arguments) }
        catch let error as ToolInputError { return result(id: id, toolError(error.message)) }
        catch { return result(id: id, toolError("Invalid arguments.")) }

        let response: ControlResponse
        do { response = try await backend.send(ControlRequest(method: method.rawValue, params: parameters)) }
        catch BackendError.dingNotRunning {
            return result(id: id, toolError("Ding isn't running. Ask the user to open Ding, then try again."))
        } catch {
            return result(id: id, toolError("Couldn't reach Ding: \(describe(error))"))
        }

        if response.ok {
            return result(id: id, toolSuccess(response.result ?? .null))
        }
        let failure = response.error ?? ControlError(code: "unknown", message: "Ding reported an error without details.")
        return result(id: id, toolError(failure.message, code: failure.code))
    }

    private func toolSuccess(_ value: JSONValue) -> [String: Any] {
        let object = value.foundationObject
        return [
            "content": [["type": "text", "text": prettyText(object)]],
            "structuredContent": object,
            "isError": false,
        ]
    }

    private func toolError(_ message: String, code: String? = nil) -> [String: Any] {
        var content: [String: Any] = ["content": [["type": "text", "text": message]], "isError": true]
        if let code { content["structuredContent"] = ["error": ["code": code, "message": message]] }
        return content
    }

    private func describe(_ error: Error) -> String {
        if case BackendError.other(let detail) = error { return detail }
        return String(describing: error)
    }

    // MARK: JSON-RPC envelopes

    private func result(id: Any, _ result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private func errorResponse(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    /// One line of compact JSON: the stdio transport frames messages by newline, so there must be none inside.
    private func encode(_ object: Any) -> Data? {
        try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
    }

    private func prettyText(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return "\(object)" }
        return String(decoding: data, as: UTF8.self)
    }
}
