import DingIPC
import DingMCP
import Foundation

// ding-mcp: Ding's MCP server. A client (Claude Desktop, Claude Code, ...) starts this program and talks to it over
// stdin and stdout; it relays tool calls to the running Ding app over a Unix socket in their shared app group.
// Nothing is printed to stdout except protocol messages.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("ding-mcp: \(message)\n".utf8))
    exit(1)
}

guard let group = Bundle.main.object(forInfoDictionaryKey: DingIPC.appGroupInfoKey) as? String,
      let socketURL = DingIPC.socketURL(appGroup: group) else {
    fail("this build has no app group configured")
}
let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
let server = MCPServer(backend: SocketBackend(path: socketURL.path), version: version)

let output = FileHandle.standardOutput
await server.serve(lines: FileHandle.standardInput.bytes.lines) { output.write($0) }
