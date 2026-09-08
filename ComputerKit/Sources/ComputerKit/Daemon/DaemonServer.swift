import CoreGraphics
import Foundation

/// Singleton daemon: owns the engine + registry, speaks MCP per client and
/// pushes supervision events.
///
/// Threading: accept runs on a dedicated queue, each client reads on the
/// global queue, shared client state is guarded by one NSRecursiveLock, and
/// all supervision-fd writes/closes go through a serial write queue.
public final class DaemonServer {
    public static let defaultSocketPath = NSHomeDirectory() + "/Library/Application Support/10x/computer.sock"

    private let engine: DesktopEngine
    private let previewInterval: TimeInterval
    private lazy var preview: PreviewStreamer = {
        let streamer = PreviewStreamer(engine: engine, interval: previewInterval) { [weak self] event in self?.broadcast(event) }
        streamer.onWindowGone = { [weak self] session, windowID in self?.handleWindowGone(session: session, windowID: windowID) }
        return streamer
    }()
    let registry = SessionRegistry()
    private let socketPath: String
    private let acceptQueue = DispatchQueue(label: "tenx-computer.accept")
    /// Serializes all supervision-fd send/close to prevent torn NDJSON and fd reuse races.
    private let writeQueue = DispatchQueue(label: "tenx-computer.supervision-writes")
    /// Recursive because handleLine may re-enter while updating shared state.
    private let lock = NSRecursiveLock()
    private var serverFD: Int32 = -1
    private var ownsSocketFile = false
    private var clients: [Int32: ClientState] = [:]
    private var isRunning = false
    /// Set by `stop_all`; never cleared — in-flight engine work aborts until daemon restart.
    private final class StopAllFlag: @unchecked Sendable {
        var value = false
    }
    private let stopAllFlag = StopAllFlag()

    private enum Role {
        case mcp(SessionID, MCPServer, ScreenshotResources)
        case supervision
    }

    private final class ClientState {
        var role: Role?
        var buffer = Data()
        let peerPID: Int32?
        init(peerPID: Int32?) { self.peerPID = peerPID }
    }

    public init(engine: DesktopEngine, socketPath: String = DaemonServer.defaultSocketPath, previewInterval: TimeInterval = 1.0) {
        self.engine = engine
        self.previewInterval = previewInterval
        self.socketPath = socketPath
    }

    /// Rejects paths that would overflow `sockaddr_un.sun_path` (104 bytes incl. NUL).
    public static func validateSocketPath(_ path: String) throws {
        let byteCount = path.utf8.count
        guard byteCount < 104 else {
            throw ComputerError("socket_path_too_long: \(byteCount) bytes (max 103)")
        }
    }

    public func start() throws {
        try Self.validateSocketPath(socketPath)
        engine.isCancelled = { [stopAllFlag] in stopAllFlag.value }

        let parent = (socketPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)

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
            if alive == 0 {
                close(serverFD)
                serverFD = -1
                throw ComputerError("daemon_already_running")
            }
            unlink(socketPath)
            let rebound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(serverFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
            guard rebound == 0 else {
                close(serverFD)
                serverFD = -1
                throw ComputerError("bind: \(String(cString: strerror(errno)))")
            }
        }
        _ = fchmod(serverFD, 0o600)
        ownsSocketFile = true

        guard listen(serverFD, 16) == 0 else {
            close(serverFD)
            serverFD = -1
            if ownsSocketFile {
                unlink(socketPath)
                ownsSocketFile = false
            }
            throw ComputerError("listen: \(String(cString: strerror(errno)))")
        }

        isRunning = true
        acceptQueue.async { [weak self] in self?.acceptLoop() }
    }

    public func stop() {
        lock.lock()
        isRunning = false
        let fds = Array(clients.keys)
        lock.unlock()
        preview.setActive(session: nil, windowID: nil)
        for fd in fds { enqueueClose(fd) }
        if serverFD >= 0 {
            close(serverFD)
            serverFD = -1
        }
        if ownsSocketFile {
            unlink(socketPath)
            ownsSocketFile = false
        }
    }

    private func acceptLoop() {
        while true {
            let clientFD = accept(serverFD, nil, nil)
            if clientFD < 0 {
                let err = errno
                if err == EINTR { continue }
                lock.lock()
                let running = isRunning
                lock.unlock()
                if !running || err == EBADF || err == EINVAL { return }
                continue
            }
            guard Self.disableSIGPIPE(clientFD) else { close(clientFD); continue }
            let peerPID = Self.peerPID(for: clientFD)
            lock.lock()
            let running = isRunning
            if running { clients[clientFD] = ClientState(peerPID: peerPID) }
            lock.unlock()
            guard running else { close(clientFD); return }
            DispatchQueue.global().async { [weak self] in self?.readLoop(clientFD) }
        }
    }

    private func readLoop(_ fd: Int32) {
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            let count = recv(fd, &chunk, chunk.count, 0)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                break
            }
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
        if clients[fd]?.role == nil {
            guard let client = clients[fd] else {
                lock.unlock()
                return
            }
            if message["role"]?.stringValue == "supervision" {
                client.role = .supervision
                let replay = replayEvents()
                lock.unlock()
                let permissions = engine.preflightPermissions()
                let ack = try? JSONEncoder().encode(JSONValue.object(["role": .string("supervision"), "ok": .bool(true)])) + Data([0x0A])
                if let ack { enqueueSupervisionWrite(fd, ack) }
                // Late-attaching subscribers (10x opened while another harness is
                // mid-control) get the current state as a replay of synthetic events.
                for event in replay {
                    if let line = try? event.jsonLine().data(using: .utf8) {
                        enqueueSupervisionWrite(fd, line + Data([0x0A]))
                    }
                }
                broadcast(.permissions(screenRecording: permissions.screenRecording, accessibility: permissions.accessibility))
            } else {
                let label = message["label"]?.stringValue
                let session = registry.registerSession(clientName: nil, label: label, peerPID: client.peerPID)
                let tools = ComputerTools(engine: engine, registry: registry, session: session)
                let resources = ScreenshotResources(engine: engine, registry: registry)
                client.role = .mcp(session, MCPServer(tools: tools, resources: resources), resources)
                lock.unlock()
            }
            return
        }
        let client = clients[fd]
        let role = client?.role
        lock.unlock()

        switch role {
        case .mcp(let session, let server, let resources):
            guard let method = message["method"]?.stringValue else { return }
            let id = message["id"]

            lock.lock()
            let claimsBefore = Set(registry.claimedWindows(for: session).map(\.id))
            let resourceReadContext: (uri: String, windowID: CGWindowID)?
            if method == "resources/read", let uri = message["params"]?["uri"]?.stringValue,
               let windowID = Self.screenshotWindowID(from: uri),
               registry.owner(of: windowID) != nil {
                resourceReadContext = (uri, windowID)
            } else {
                resourceReadContext = nil
            }
            lock.unlock()

            var response: JSONValue?
            var events: [SupervisionEvent] = []
            var previewAction: (session: SessionID, windowID: CGWindowID)?
            var previewStop: (session: SessionID, windowID: CGWindowID)?
            var handleResult: JSONValue?

            if let resourceReadContext {
                if let resource = resources.readResource(uri: resourceReadContext.uri) {
                    response = .object([
                        "jsonrpc": .string("2.0"), "id": id ?? .null,
                        "result": .object(["contents": .array([resource])]),
                    ])
                } else {
                    response = errorResponse(id: id, code: -32602, message: "capture_failed: could not capture \(resourceReadContext.uri)")
                }
            } else {
                do {
                    handleResult = try server.handle(method: method, params: message["params"])
                    if let result = handleResult {
                        if method == "initialize", let name = server.clientName {
                            lock.lock()
                            registry.setHarness(name, for: session)
                            let info = registry.session(session)
                            events.append(.sessionStarted(
                                session: session.raw, harness: name,
                                label: info?.label, pid: info?.peerPID
                            ))
                            lock.unlock()
                        }
                        let isError = result["isError"]?.boolValue == true
                        if method == "tools/call" {
                            if isError {
                                handleWindowGoneCleanup(from: result, session: session)
                            } else {
                                let toolResult = toolEvents(
                                    session: session, method: method, params: message["params"], claimsBefore: claimsBefore
                                )
                                events.append(contentsOf: toolResult.events)
                                previewAction = toolResult.previewAction
                                previewStop = toolResult.previewStop
                            }
                        }
                        response = .object(["jsonrpc": .string("2.0"), "id": id ?? .null, "result": result])
                    }
                } catch let error as MCPError {
                    response = errorResponse(id: id, code: error.code, message: error.message)
                } catch let error as ComputerError {
                    response = errorResponse(id: id, code: -32603, message: error.message)
                } catch {
                    response = errorResponse(id: id, code: -32603, message: "\(error)")
                }
            }

            for event in events { broadcast(event) }
            if let previewAction {
                preview.actionOccurred(session: previewAction.session, windowID: previewAction.windowID)
            }
            if let previewStop {
                preview.stopPreview(for: previewStop.session, windowID: previewStop.windowID)
            }
            if let response { try? write(fd, response) }

        case .supervision:
            if let command = message["command"]?.stringValue {
                switch command {
                case "stop_session":
                    if let raw = message["session"]?.intValue {
                        let session = SessionID(raw: raw)
                        lock.lock()
                        let releases = releaseEvents(for: session, reason: "stopped")
                        let harness = registry.session(session)?.harness ?? "unknown"
                        registry.stop(session)
                        lock.unlock()
                        preview.stopPreview(for: session)
                        for event in releases { broadcast(event) }
                        broadcast(.sessionEnded(session: raw, harness: harness))
                        broadcast(.stopped(reason: "session \(raw) stopped", session: raw))
                    }
                case "stop_all":
                    lock.lock()
                    stopAllFlag.value = true
                    let stoppedSessions = registry.allSessions.filter { $0.value.isActive }.map { (id: $0.key, harness: $0.value.harness) }
                    let releases = releaseAllEvents(reason: "shutoff")
                    registry.stopAll()
                    lock.unlock()
                    preview.setActive(session: nil, windowID: nil)
                    for event in releases { broadcast(event) }
                    for stopped in stoppedSessions {
                        broadcast(.sessionEnded(session: stopped.id.raw, harness: stopped.harness))
                    }
                    broadcast(.stopped(reason: "global shut-off", session: nil))
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

    private func handleWindowGone(session: SessionID, windowID: CGWindowID) {
        lock.lock()
        defer { lock.unlock() }
        guard registry.owner(of: windowID) == session else { return }
        broadcast(.windowReleased(session: session.raw, windowID: Int(windowID), reason: "window_gone"))
        registry.windowClosed(windowID)
    }

    private func handleWindowGoneCleanup(from result: JSONValue, session: SessionID) {
        guard result["isError"]?.boolValue == true,
              let text = result["content"]?.arrayValue?.first?["text"]?.stringValue,
              text.hasPrefix("window_gone:"),
              let windowID = Self.windowIDFromGoneMessage(text) else { return }
        lock.lock()
        defer { lock.unlock() }
        if registry.owner(of: windowID) == session {
            broadcast(.windowReleased(session: session.raw, windowID: Int(windowID), reason: "window_gone"))
        }
        if registry.window(windowID) != nil {
            registry.windowClosed(windowID)
        }
    }

    private func releaseEvents(for session: SessionID, reason: String) -> [SupervisionEvent] {
        registry.claimedWindows(for: session).map {
            .windowReleased(session: session.raw, windowID: Int($0.id), reason: reason)
        }
    }

    private func releaseAllEvents(reason: String) -> [SupervisionEvent] {
        registry.allSessions.keys.flatMap { releaseEvents(for: $0, reason: reason) }
    }

    private struct ToolEventResult {
        var events: [SupervisionEvent]
        var previewAction: (session: SessionID, windowID: CGWindowID)?
        var previewStop: (session: SessionID, windowID: CGWindowID)?
    }

    /// Collects supervision events for a completed tools/call. Claims are diffed
    /// around the call so computer_launch (whose window id is only known after
    /// execution) is covered by the same path as computer_claim.
    private func toolEvents(session: SessionID, method: String, params: JSONValue?, claimsBefore: Set<CGWindowID>) -> ToolEventResult {
        guard method == "tools/call", let name = params?["name"]?.stringValue else {
            return ToolEventResult(events: [], previewAction: nil, previewStop: nil)
        }
        var events: [SupervisionEvent] = []
        var previewAction: (session: SessionID, windowID: CGWindowID)?
        var previewStop: (session: SessionID, windowID: CGWindowID)?
        let newClaims = registry.claimedWindows(for: session).filter { !claimsBefore.contains($0.id) }
        let harness = registry.session(session)?.harness ?? "unknown"
        for window in newClaims {
            events.append(.windowClaimed(
                session: session.raw, harness: harness, windowID: Int(window.id),
                app: window.appName, title: window.title,
                bounds: "\(Int(window.bounds.minX)),\(Int(window.bounds.minY)) \(Int(window.bounds.width))x\(Int(window.bounds.height))"
            ))
        }
        let args = params?["arguments"]
        switch name {
        case "computer_release":
            if let windowID = args?["window_id"]?.intValue {
                events.append(.windowReleased(session: session.raw, windowID: windowID, reason: "released"))
                previewStop = (session, CGWindowID(windowID))
            }
        case "computer_act":
            let windowID = args?["window_id"]?.intValue ?? 0
            let kind = args?["action"]?.stringValue ?? "?"
            let window = registry.window(CGWindowID(windowID))
            let points = ActionEventPoints.from(arguments: args, window: window)
            events.append(.action(
                session: session.raw, windowID: windowID, kind: kind,
                x: points.x, y: points.y
            ))
            if let windowID = args?["window_id"]?.intValue {
                previewAction = (session, CGWindowID(windowID))
            }
        case "computer_status":
            let stored = registry.session(session)?.status ?? ""
            events.append(.statusChanged(session: session.raw, status: stored))
        default:
            break
        }
        return ToolEventResult(events: events, previewAction: previewAction, previewStop: previewStop)
    }

    /// Current registry state as synthetic events, replayed to a new supervision
    /// subscriber so late attachers see pre-existing sessions and claims.
    private func replayEvents() -> [SupervisionEvent] {
        registry.allSessions.values.filter(\.isActive).sorted { $0.id.raw < $1.id.raw }.flatMap { info -> [SupervisionEvent] in
            var events: [SupervisionEvent] = [
                .sessionStarted(session: info.id.raw, harness: info.harness, label: info.label, pid: info.peerPID),
            ]
            events += registry.claimedWindows(for: info.id).map { window in
                .windowClaimed(
                    session: info.id.raw, harness: info.harness, windowID: Int(window.id),
                    app: window.appName, title: window.title,
                    bounds: "\(Int(window.bounds.minX)),\(Int(window.bounds.minY)) \(Int(window.bounds.width))x\(Int(window.bounds.height))"
                )
            }
            if let status = info.status {
                events.append(.statusChanged(session: info.id.raw, status: status))
            }
            return events
        }
    }

    private func broadcast(_ event: SupervisionEvent) {
        guard let data = try? event.jsonLine().data(using: .utf8) else { return }
        let line = data + Data([0x0A])
        lock.lock()
        let supervisionFDs = clients.compactMap { fd, client -> Int32? in
            guard case .supervision = client.role else { return nil }
            return fd
        }
        lock.unlock()
        for fd in supervisionFDs {
            enqueueSupervisionWrite(fd, line)
        }
    }

    private func enqueueSupervisionWrite(_ fd: Int32, _ data: Data) {
        writeQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.writeRaw(fd, data)
            } catch {
                self.removeClient(fd)
            }
        }
    }

    private func enqueueClose(_ fd: Int32) {
        writeQueue.async {
            shutdown(fd, SHUT_RDWR)
            close(fd)
        }
    }

    private func removeClient(_ fd: Int32) {
        lock.lock()
        clients.removeValue(forKey: fd)
        lock.unlock()
    }

    private func disconnect(_ fd: Int32) {
        lock.lock()
        guard let client = clients.removeValue(forKey: fd) else {
            lock.unlock()
            return
        }
        var events: [SupervisionEvent] = []
        var disconnectedSession: SessionID?
        if case .mcp(let session, _, _) = client.role {
            disconnectedSession = session
            events.append(contentsOf: releaseEvents(for: session, reason: "disconnect"))
            let harness = registry.session(session)?.harness ?? "unknown"
            events.append(.sessionEnded(session: session.raw, harness: harness))
            registry.removeSession(session)
        }
        lock.unlock()
        if let disconnectedSession { preview.stopPreview(for: disconnectedSession) }
        for event in events { broadcast(event) }
        enqueueClose(fd)
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
                if count < 0 {
                    if errno == EINTR { continue }
                    throw ComputerError("send failed")
                }
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

    private static func peerPID(for fd: Int32) -> Int32? {
        var pid: Int32 = 0
        var len = socklen_t(MemoryLayout.size(ofValue: pid))
        let result = getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &len)
        return result == 0 ? pid : nil
    }

    private static func disableSIGPIPE(_ fd: Int32) -> Bool {
        var nosigpipe: Int32 = 1
        return setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout.size(ofValue: nosigpipe))) == 0
    }
}

private let LOCAL_PEERPID: Int32 = 0x002
