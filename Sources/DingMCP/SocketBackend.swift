import DingIPC
import Foundation

/// Reaches the app over its Unix socket.
public struct SocketBackend: ControlBackend {
    private let client: ControlSocketClient

    public init(path: String, timeout: TimeInterval = 10) {
        client = ControlSocketClient(path: path, timeout: timeout)
    }

    public func send(_ request: ControlRequest) async throws -> ControlResponse {
        let payload = try JSONEncoder().encode(request)
        let client = self.client
        let reply: Data
        do {
            // The socket calls block, so keep them off the async executor's threads.
            reply = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global().async {
                    do { continuation.resume(returning: try client.request(payload)) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        } catch DingIPCError.notListening {
            throw BackendError.dingNotRunning
        } catch DingIPCError.timedOut {
            throw BackendError.other("Ding didn't answer in time.")
        } catch DingIPCError.closed {
            // The app hung up without an answer: it refused this program (or quit mid-request).
            throw BackendError.other("Ding closed the connection. If Ding was just updated or restarted, try again.")
        } catch {
            throw BackendError.other("\(error)")
        }
        do { return try JSONDecoder().decode(ControlResponse.self, from: reply) }
        catch { throw BackendError.other("Ding sent a reply this helper couldn't read.") }
    }
}

extension MCPServer {
    /// Serves a stream of newline-delimited messages, writing each reply followed by a newline. Returns when the
    /// stream ends, which is how the client says it is done.
    public func serve<Lines: AsyncSequence>(lines: Lines, write: (Data) -> Void) async where Lines.Element == String {
        do {
            for try await line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                if let reply = await handle(Data(trimmed.utf8)) {
                    write(reply + Data([UInt8(ascii: "\n")]))
                }
            }
        } catch {
            // The input closed badly; there is nobody left to tell.
        }
    }
}
