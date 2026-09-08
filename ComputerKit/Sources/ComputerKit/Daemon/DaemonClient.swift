import Foundation

/// NDJSON client for the daemon socket — used by the MCP proxy, stop-all,
/// tests, and (in Plan 2) the 10x app's supervision subscription.
public final class DaemonClient {
    private let fd: Int32
    private var buffer = Data()

    public init(socketPath: String = DaemonServer.defaultSocketPath) throws {
        try DaemonServer.validateSocketPath(socketPath)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ComputerError("socket: \(String(cString: strerror(errno)))") }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            socketPath.withCString { strncpy(UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self), $0, 104) }
        }
        let connected = withUnsafePointer(to: &address) { addressPointer in
            addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            close(fd)
            throw ComputerError("daemon_unreachable: \(socketPath)")
        }
        Self.disableSIGPIPE(fd)
    }

    deinit { close(fd) }

    private static func disableSIGPIPE(_ fd: Int32) {
        var nosigpipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout.size(ofValue: nosigpipe)))
    }

    public func send(_ value: JSONValue) throws {
        let data = try JSONEncoder().encode(value) + Data([0x0A])
        try sendBytes(data)
    }

    func sendBytes(_ data: Data) throws {
        try data.withUnsafeBytes { pointer in
            guard let base = pointer.baseAddress else { return }
            var sent = 0
            while sent < data.count {
                let count = Darwin.send(fd, base + sent, data.count - sent, 0)
                guard count > 0 else { throw ComputerError("send failed") }
                sent += count
            }
        }
    }

    public func receive(timeout: TimeInterval? = nil) throws -> JSONValue {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer.prefix(upTo: newline)
                buffer.removeSubrange(...newline)
                return try JSONDecoder().decode(JSONValue.self, from: line)
            }
            if let timeout {
                var pollFD = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                let milliseconds = Int32((timeout * 1000).rounded())
                let ready = poll(&pollFD, 1, milliseconds)
                if ready == 0 { throw ComputerError("receive_timeout") }
                if ready < 0 {
                    if errno == EINTR { continue }
                    throw ComputerError("poll: \(String(cString: strerror(errno)))")
                }
                if pollFD.revents & Int16(POLLERR | POLLHUP | POLLNVAL) != 0 {
                    throw ComputerError("daemon_closed")
                }
            }
            var chunk = [UInt8](repeating: 0, count: 65536)
            let count = recv(fd, &chunk, chunk.count, 0)
            if count < 0 {
                if errno == EINTR { continue }
                throw ComputerError("daemon_closed")
            }
            guard count > 0 else { throw ComputerError("daemon_closed") }
            buffer.append(contentsOf: chunk[0..<count])
        }
    }
}
