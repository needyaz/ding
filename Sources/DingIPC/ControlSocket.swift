import Darwin
import Foundation
import Security

/// Serves framed requests on a Unix socket, one thread per connection. Every connection is checked against
/// a code signing requirement before a single byte is read.
public final class ControlSocketServer: @unchecked Sendable {
    public typealias Handler = @Sendable (Data) async -> Data

    private let path: String
    private let requirement: String?
    private let handler: Handler
    private var listenFD: Int32 = -1
    private let lock = NSLock()
    private var openConnections = 0

    /// Only the helper connects, and it opens one short connection per request, so these are generous. They bound what
    /// a stuck or misbehaving peer can hold: a thread each, for no longer than `idleTimeout` without a request.
    private let maxConnections: Int
    private let idleTimeout: TimeInterval

    public init(path: String, requirement: String?, maxConnections: Int = 16, idleTimeout: TimeInterval = 30, handler: @escaping Handler) {
        self.path = path
        self.requirement = requirement
        self.maxConnections = maxConnections
        self.idleTimeout = idleTimeout
        self.handler = handler
    }

    public func start() throws {
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw DingIPCError.socket("socket: \(String(cString: strerror(errno)))") }
        var address = try Self.address(for: path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0 else { close(fd); throw DingIPCError.socket("bind: \(String(cString: strerror(errno)))") }
        chmod(path, 0o600)
        guard listen(fd, 8) == 0 else { close(fd); throw DingIPCError.socket("listen: \(String(cString: strerror(errno)))") }
        lock.lock(); listenFD = fd; lock.unlock()
        let thread = Thread { [weak self] in self?.acceptLoop(fd) }
        thread.name = "ding.control.accept"
        thread.start()
    }

    public func stop() {
        lock.lock(); let fd = listenFD; listenFD = -1; lock.unlock()
        if fd >= 0 { close(fd); unlink(path) }
    }

    private func acceptLoop(_ fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return  // closed by stop()
            }
            guard reserveConnection() else { close(client); continue }
            var one: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            // A peer that stops talking is dropped instead of holding its thread forever.
            let whole = idleTimeout.rounded(.down)
            var tv = timeval(tv_sec: Int(whole), tv_usec: suseconds_t((idleTimeout - whole) * 1_000_000))
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            let thread = Thread { [handler, requirement, weak self] in
                defer { close(client); self?.releaseConnection() }
                if let requirement, !PeerVerifier.peerSatisfies(requirement, fd: client) { return }
                Self.serve(client, handler: handler)
            }
            thread.name = "ding.control.client"
            thread.start()
        }
    }

    private func reserveConnection() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard openConnections < maxConnections else { return false }
        openConnections += 1
        return true
    }

    private func releaseConnection() {
        lock.lock(); openConnections -= 1; lock.unlock()
    }

    private static func serve(_ fd: Int32, handler: @escaping Handler) {
        while let request = try? Framing.read(from: fd) {
            let semaphore = DispatchSemaphore(value: 0)
            var response = Data()
            Task { response = await handler(request); semaphore.signal() }
            semaphore.wait()
            if (try? Framing.write(response, to: fd)) == nil { return }
        }
    }

    static func address(for path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else { throw DingIPCError.socket("socket path too long (\(bytes.count) bytes)") }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
            buffer[bytes.count] = 0
        }
        return address
    }
}

/// Sends one framed request and waits for the framed response.
///
/// The client doesn't verify who it is talking to: a sandboxed process isn't allowed to inspect another
/// process's code signature. The socket sits in the app group container, and the server is the side that
/// checks who connects.
public struct ControlSocketClient: Sendable {
    public let path: String
    public let timeout: TimeInterval

    public init(path: String, timeout: TimeInterval = 10) {
        self.path = path
        self.timeout = timeout
    }

    public func request(_ data: Data) throws -> Data {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw DingIPCError.socket("socket: \(String(cString: strerror(errno)))") }
        defer { close(fd) }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        // A zero timeval means "wait forever", so a short timeout must never round down to it.
        let whole = timeout.rounded(.down)
        var tv = timeval(tv_sec: Int(whole), tv_usec: suseconds_t(max((timeout - whole) * 1_000_000, whole > 0 ? 0 : 1_000)))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var address = try ControlSocketServer.address(for: path)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else {
            let code = errno
            // No file, or a file nobody is listening on (left behind by a crash): the server isn't running.
            if code == ENOENT || code == ECONNREFUSED { throw DingIPCError.notListening }
            throw DingIPCError.socket("connect: \(String(cString: strerror(code)))")
        }

        try Framing.write(data, to: fd)
        guard let response = try Framing.read(from: fd) else { throw DingIPCError.closed }
        return response
    }
}
