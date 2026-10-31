import Darwin
import Foundation
import Security

public enum DingIPCError: Error, Equatable {
    /// Nothing is listening on the socket: the file is missing or refuses connections.
    case notListening
    case socket(String)
    case closed
    case frameTooLarge
    case unauthorized
    case timedOut
}

/// Length-prefixed frames over a stream socket: a 4-byte big-endian length, then that many bytes.
public enum Framing {
    public static let maxFrameSize = 1 << 20

    public static func write(_ data: Data, to fd: Int32) throws {
        guard data.count <= maxFrameSize else { throw DingIPCError.frameTooLarge }
        var length = UInt32(data.count).bigEndian
        var packet = Data(bytes: &length, count: 4)
        packet.append(data)
        try packet.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let n = Darwin.write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw errno == EAGAIN || errno == EWOULDBLOCK ? DingIPCError.timedOut : DingIPCError.socket("write: \(String(cString: strerror(errno)))")
                }
                offset += n
            }
        }
    }

    /// The next frame, or nil if the peer closed the connection between frames.
    public static func read(from fd: Int32) throws -> Data? {
        guard let header = try readExactly(4, from: fd, allowEOFAtStart: true) else { return nil }
        let length = Int(header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian })
        guard length <= maxFrameSize else { throw DingIPCError.frameTooLarge }
        if length == 0 { return Data() }
        guard let body = try readExactly(length, from: fd, allowEOFAtStart: false) else { throw DingIPCError.closed }
        return body
    }

    private static func readExactly(_ count: Int, from fd: Int32, allowEOFAtStart: Bool) throws -> Data? {
        var data = Data(count: count)
        var offset = 0
        while offset < count {
            let n = data.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress! + offset, count - offset) }
            if n < 0 {
                if errno == EINTR { continue }
                throw errno == EAGAIN || errno == EWOULDBLOCK ? DingIPCError.timedOut : DingIPCError.socket("read: \(String(cString: strerror(errno)))")
            }
            if n == 0 {
                if offset == 0 && allowEOFAtStart { return nil }
                throw DingIPCError.closed
            }
            offset += n
        }
        return data
    }
}

/// Checks who is on the other end of a connected Unix socket by its code signature.
public enum PeerVerifier {
    /// True if the process at the other end of `fd` satisfies the code signing `requirement`.
    public static func peerSatisfies(_ requirement: String, fd: Int32) -> Bool {
        check(requirement, fd: fd) == errSecSuccess
    }

    /// `errSecSuccess` if the peer satisfies `requirement`; otherwise the failing Security or socket status.
    public static func check(_ requirement: String, fd: Int32) -> OSStatus {
        var token = audit_token_t()
        var length = socklen_t(MemoryLayout<audit_token_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &length) == 0 else { return OSStatus(-errno) }
        let attributes = [kSecGuestAttributeAudit: Data(bytes: &token, count: Int(length))] as CFDictionary

        var code: SecCode?
        let guest = SecCodeCopyGuestWithAttributes(nil, attributes, [], &code)
        guard guest == errSecSuccess, let code else { return guest }
        var parsed: SecRequirement?
        let created = SecRequirementCreateWithString(requirement as CFString, [], &parsed)
        guard created == errSecSuccess, let parsed else { return created }
        return SecCodeCheckValidity(code, [], parsed)
    }
}
