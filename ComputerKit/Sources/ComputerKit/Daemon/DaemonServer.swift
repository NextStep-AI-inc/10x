import CoreGraphics
import Foundation

/// Singleton daemon: owns the engine + registry, speaks MCP per client and
/// pushes supervision events.
///
/// Threading: accept runs on a dedicated queue, each client reads on the
/// global queue, and ALL shared state (clients, registry) is guarded by one
/// NSRecursiveLock. Event volume is tiny, so a single lock is correct and sufficient.
public final class DaemonServer {
    public static let defaultSocketPath = NSHomeDirectory() + "/Library/Application Support/10x/computer.sock"

    private let engine: DesktopEngine
    let registry = SessionRegistry()
    private let socketPath: String
    private let acceptQueue = DispatchQueue(label: "tenx-computer.accept")
    /// Recursive because broadcast/emitToolEvents re-enter while handleLine holds it.
    private let lock = NSRecursiveLock()
    private var serverFD: Int32 = -1
    private var clients: [Int32: ClientState] = [:]
    private var isRunning = false

    private enum Role {
        case mcp(SessionID, MCPServer, ScreenshotResources)
        case supervision
    }

    private final class ClientState {
        var role: Role?
        var buffer = Data()
    }

    public init(engine: DesktopEngine, socketPath: String = DaemonServer.defaultSocketPath) {
        self.engine = engine
        self.socketPath = socketPath
    }

    public func start() throws {
        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else { throw ComputerError("socket: \(String(cString: strerror(errno)))") }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            socketPath.withCString { strncpy(UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self), $0, 104) }
        }
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(serverFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }

        if bound != 0 {
            // ponytail: stale-socket recovery is connect-fail-then-unlink.
            // Ceiling: two daemons started in the same instant can both pass the
            // connect probe. Upgrade path: flock a sibling .lock file.
            let alive = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(serverFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
            guard alive != 0 else { throw ComputerError("daemon_already_running") }
            unlink(socketPath)
            let rebound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(serverFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
            guard rebound == 0 else { throw ComputerError("bind: \(String(cString: strerror(errno)))") }
        }
        guard listen(serverFD, 16) == 0 else { throw ComputerError("listen: \(String(cString: strerror(errno)))") }

        isRunning = true
        acceptQueue.async { [weak self] in self?.acceptLoop() }
    }

    public func stop() {
        lock.lock()
        isRunning = false
        let fds = Array(clients.keys)
        clients.removeAll()
        lock.unlock()
        for fd in fds { close(fd) }
        if serverFD >= 0 { close(serverFD); serverFD = -1 }
        unlink(socketPath)
    }

    private func acceptLoop() {
        while true {
            let clientFD = accept(serverFD, nil, nil)
            guard clientFD >= 0 else { return }
            lock.lock()
            let running = isRunning
            if running { clients[clientFD] = ClientState() }
            lock.unlock()
            guard running else { close(clientFD); return }
            Self.disableSIGPIPE(clientFD)
            DispatchQueue.global().async { [weak self] in self?.readLoop(clientFD) }
        }
    }

    private func readLoop(_ fd: Int32) {
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            let count = recv(fd, &chunk, chunk.count, 0)
            guard count > 0 else { break }
            lock.lock()
            clients[fd]?.buffer.append(contentsOf: chunk[0..<count])
            var lines: [Data] = []
            while let newline = clients[fd]?.buffer.firstIndex(of: 0x0A) {
                lines.append(Data(clients[fd]!.buffer.prefix(upTo: newline)))
                clients[fd]!.buffer.removeSubrange(...newline)
            }
            lock.unlock()
            for line in lines { handleLine(fd: fd, line: line) }
        }
        disconnect(fd)
    }

    private func handleLine(fd: Int32, line: Data) {
        guard let message = try? JSONDecoder().decode(JSONValue.self, from: line) else { return }

        lock.lock()
        let client = clients[fd]
        if client?.role == nil {
            if message["role"]?.stringValue == "supervision" {
                client?.role = .supervision
                lock.unlock()
                // Ack so subscribers know events after this point are guaranteed.
                try? write(fd, .object(["role": .string("supervision"), "ok": .bool(true)]))
            } else {
                let session = registry.registerSession(clientName: nil)
                let tools = ComputerTools(engine: engine, registry: registry, session: session)
                let resources = ScreenshotResources(engine: engine, registry: registry)
                client?.role = .mcp(session, MCPServer(tools: tools, resources: resources), resources)
                lock.unlock()
            }
            return
        }
        let role = client?.role
        lock.unlock()

        switch role {
        case .mcp(let session, let server, let resources):
            guard let method = message["method"]?.stringValue else { return }
            let id = message["id"]
            // ponytail: MCP work is serialized across clients — computer use is
            // inherently serial per machine (one input stream), so this costs
            // little. Ceiling: a slow screenshot blocks another session's call
            // for its duration. Upgrade path: per-session queues + engine pool.
            lock.lock()
            defer { lock.unlock() }
            let claimsBefore = Set(registry.claimedWindows(for: session).map(\.id))

            if method == "resources/read", let uri = message["params"]?["uri"]?.stringValue,
               let windowID = Self.screenshotWindowID(from: uri),
               registry.owner(of: windowID) != nil {
                if let resource = resources.readResource(uri: uri) {
                    try? write(fd, .object([
                        "jsonrpc": .string("2.0"), "id": id ?? .null,
                        "result": .object(["contents": .array([resource])]),
                    ]))
                } else {
                    try? write(fd, errorResponse(id: id, code: -32602, message: "capture_failed: could not capture \(uri)"))
                }
                return
            }

            do {
                if let result = try server.handle(method: method, params: message["params"]) {
                    if method == "initialize", let name = server.clientName {
                        registry.setHarness(name, for: session)
                        broadcast(.sessionStarted(session: session.raw, harness: name))
                    }
                    if method == "tools/call" {
                        handleWindowGoneCleanup(from: result)
                    }
                    emitToolEvents(session: session, method: method, params: message["params"], claimsBefore: claimsBefore)
                    try write(fd, .object(["jsonrpc": .string("2.0"), "id": id ?? .null, "result": result]))
                }
            } catch let error as MCPError {
                try? write(fd, errorResponse(id: id, code: error.code, message: error.message))
            } catch let error as ComputerError {
                try? write(fd, errorResponse(id: id, code: -32603, message: error.message))
            } catch {
                try? write(fd, errorResponse(id: id, code: -32603, message: "\(error)"))
            }

        case .supervision:
            if let command = message["command"]?.stringValue {
                switch command {
                case "stop_session":
                    if let raw = message["session"]?.intValue {
                        lock.lock()
                        registry.stop(SessionID(raw: raw))
                        lock.unlock()
                        broadcast(.stopped(reason: "session \(raw) stopped"))
                    }
                case "stop_all":
                    lock.lock()
                    registry.stopAll()
                    lock.unlock()
                    broadcast(.stopped(reason: "global shut-off"))
                default:
                    break
                }
            } else {
                let lineText = String(decoding: line, as: UTF8.self)
                guard (try? SupervisionEvent(jsonLine: lineText)) != nil else { return }
            }

        case .none:
            break
        }
    }

    private func handleWindowGoneCleanup(from result: JSONValue) {
        guard result["isError"]?.boolValue == true,
              let text = result["content"]?.arrayValue?.first?["text"]?.stringValue,
              text.hasPrefix("window_gone:"),
              let windowID = Self.windowIDFromGoneMessage(text),
              registry.window(windowID) != nil else { return }
        registry.windowClosed(windowID)
    }

    /// Emits supervision events for a completed tools/call. Claims are diffed
    /// around the call so computer_launch (whose window id is only known after
    /// execution) is covered by the same path as computer_claim.
    private func emitToolEvents(session: SessionID, method: String, params: JSONValue?, claimsBefore: Set<CGWindowID>) {
        guard method == "tools/call", let name = params?["name"]?.stringValue else { return }
        let newClaims = registry.claimedWindows(for: session).filter { !claimsBefore.contains($0.id) }
        let harness = registry.session(session)?.harness ?? "unknown"
        for window in newClaims {
            broadcast(.windowClaimed(
                session: session.raw, harness: harness, windowID: Int(window.id),
                app: window.appName, title: window.title,
                bounds: "\(Int(window.bounds.minX)),\(Int(window.bounds.minY)) \(Int(window.bounds.width))x\(Int(window.bounds.height))"
            ))
        }
        let args = params?["arguments"]
        switch name {
        case "computer_release":
            if let windowID = args?["window_id"]?.intValue {
                broadcast(.windowReleased(session: session.raw, windowID: windowID, reason: "released"))
            }
        case "computer_act":
            broadcast(.action(
                session: session.raw,
                windowID: args?["window_id"]?.intValue ?? 0,
                kind: args?["action"]?.stringValue ?? "?",
                x: args?["x"]?.doubleValue ?? 0,
                y: args?["y"]?.doubleValue ?? 0
            ))
        case "computer_status":
            broadcast(.statusChanged(session: session.raw, status: args?["status"]?.stringValue ?? ""))
        default:
            break
        }
    }

    private func broadcast(_ event: SupervisionEvent) {
        guard let data = try? event.jsonLine().data(using: .utf8) else { return }
        lock.lock()
        let supervisionFDs = clients.compactMap { fd, client -> Int32? in
            guard case .supervision = client.role else { return nil }
            return fd
        }
        lock.unlock()
        // ponytail: sends happen outside the lock; payloads are tiny and local.
        for fd in supervisionFDs { _ = try? writeRaw(fd, data + Data([0x0A])) }
    }

    private func disconnect(_ fd: Int32) {
        lock.lock()
        let client = clients.removeValue(forKey: fd)
        var ended: (Int, String)?
        if case .mcp(let session, _, _) = client?.role {
            let harness = registry.session(session)?.harness ?? "unknown"
            registry.stop(session)
            ended = (session.raw, harness)
        }
        lock.unlock()
        if let ended { broadcast(.sessionEnded(session: ended.0, harness: ended.1)) }
        close(fd)
    }

    private func errorResponse(id: JSONValue?, code: Int, message: String) -> JSONValue {
        .object([
            "jsonrpc": .string("2.0"), "id": id ?? .null,
            "error": .object(["code": .number(Double(code)), "message": .string(message)]),
        ])
    }

    private func write(_ fd: Int32, _ value: JSONValue) throws {
        try writeRaw(fd, JSONEncoder().encode(value) + Data([0x0A]))
    }

    private func writeRaw(_ fd: Int32, _ data: Data) throws {
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

    private static func screenshotWindowID(from uri: String) -> CGWindowID? {
        guard uri.hasPrefix("computer://window/"), uri.hasSuffix("/screenshot"),
              let id = Int(uri.dropFirst("computer://window/".count).dropLast("/screenshot".count)) else { return nil }
        return CGWindowID(exactly: id)
    }

    private static func windowIDFromGoneMessage(_ message: String) -> CGWindowID? {
        guard message.hasPrefix("window_gone:") else { return nil }
        let idPart = message.dropFirst("window_gone:".count).trimmingCharacters(in: .whitespaces)
        guard let id = Int(idPart) else { return nil }
        return CGWindowID(exactly: id)
    }

    private static func disableSIGPIPE(_ fd: Int32) {
        var nosigpipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout.size(ofValue: nosigpipe)))
    }
}
