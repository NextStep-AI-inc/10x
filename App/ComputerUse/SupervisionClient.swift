import ComputerKit
import Foundation
import Observation

public struct ClaimedWindowState: Equatable, Identifiable, Sendable {
    public let windowID: Int
    public var app: String
    public var title: String
    public var bounds: String
    public var id: Int { windowID }
}

public struct ComputerSessionState: Equatable, Identifiable, Sendable {
    public let id: Int
    public var harness: String
    public var label: String?
    public var status: String?
    public var windows: [ClaimedWindowState] = []
}

/// App-wide view of the tenx-computer daemon. Owns the supervision socket;
/// UI reads the snapshot. Reconnects with a slow poll while the daemon is
/// absent — it starts on first MCP use, so absence is the normal idle state.
@Observable
public final class SupervisionClient: @unchecked Sendable {
    public private(set) var sessions: [Int: ComputerSessionState] = [:]
    public private(set) var frames: [Int: Data] = [:] // windowID -> latest PNG
    public private(set) var lastAction: (windowID: Int, kind: String, x: Double?, y: Double?, at: Date)?
    public private(set) var isConnected = false
    public private(set) var permissions: (screenRecording: Bool, accessibility: Bool)?

    /// True when any harness has a claimed window — drives MenuBarExtra insertion.
    public var hasAnyActivity: Bool {
        sessions.values.contains { !$0.windows.isEmpty }
    }

    private let socketPath: String
    private var listenTask: Task<Void, Never>?
    private let clientBox = Locked<DaemonClient?>(nil)

    /// Side-channel for per-session forwarding — AppModel sets this to route
    /// events to the active session's ComputerUseController.
    public var onEvent: ((SupervisionEvent) -> Void)?

    public init(socketPath: String = DaemonServer.defaultSocketPath) {
        self.socketPath = socketPath
    }

    public func start() {
        guard listenTask == nil else { return }
        listenTask = Task.detached { [weak self] in await self?.listenLoop() }
    }

    public func stop() {
        listenTask?.cancel()
        listenTask = nil
        let client = clientBox.with { current -> DaemonClient? in
            defer { current = nil }
            return current
        }
        client?.close()
    }

    public func stopSession(_ sessionID: Int) async {
        let path = socketPath
        let payload: ComputerKit.JSONValue = .object([
            "command": .string("stop_session"),
            "session": .number(Double(sessionID)),
        ])
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                defer { continuation.resume() }
                guard let client = try? DaemonClient(socketPath: path) else { return }
                try? client.send(.object(["role": .string("supervision")]))
                // Drain handshake (ack → replay → permissions) so the command
                // isn't racing a socket the daemon still considers mid-handshake.
                // Wall-clock cap: a chatty daemon (preview heartbeat) must not
                // hold Stop hostage — delivery doesn't require seeing permissions.
                let deadline = Date().addingTimeInterval(3)
                while Date() < deadline {
                    guard let line = try? client.receive(timeout: 2) else { break }
                    if line["type"] == .string("permissions") { break }
                }
                try? client.send(payload)
            }
        }
    }

    public func stopAll() {
        send(.object(["command": .string("stop_all")]))
    }

    private func send(_ command: ComputerKit.JSONValue) {
        Task.detached { [socketPath] in
            guard let client = try? DaemonClient(socketPath: socketPath) else { return }
            try? client.send(.object(["role": .string("supervision")]))
            _ = try? client.receive() // handshake ack
            try? client.send(command)
        }
    }

    private func listenLoop() async {
        var published: DaemonClient?
        while !Task.isCancelled {
            do {
                let client = try DaemonClient(socketPath: socketPath)
                published = client
                clientBox.with { $0 = client }
                if Task.isCancelled {
                    client.close()
                    clientBox.with { if $0 === client { $0 = nil } }
                    break
                }
                try client.send(.object(["role": .string("supervision")]))
                _ = try client.receive() // handshake ack
                await MainActor.run { self.isConnected = true }
                while !Task.isCancelled {
                    let line = try client.receive()
                    let event = try SupervisionEvent(jsonLine: String(decoding: try JSONEncoder().encode(line), as: UTF8.self))
                    await MainActor.run { self.apply(event) }
                }
            } catch {
                await MainActor.run { self.isConnected = false }
                // ponytail: fixed 2s retry — the daemon appears on first MCP use
                // and events are state-rebuildable, so no backoff sophistication.
                try? await Task.sleep(for: .seconds(2))
            }
        }
        // Identity-guarded: a stop()/start() race must not clear the new loop's client.
        if let published { clientBox.with { if $0 === published { $0 = nil } } }
    }

    /// Pure reducer — the tested surface.
    public func apply(_ event: SupervisionEvent) {
        switch event {
        case .sessionStarted(let session, let harness, let label, _):
            sessions[session] = ComputerSessionState(id: session, harness: harness, label: label)
        case .sessionEnded(let session, _):
            if let ended = sessions.removeValue(forKey: session) {
                for window in ended.windows { frames.removeValue(forKey: window.windowID) }
            }
        case .windowClaimed(let session, _, let windowID, let app, let title, let bounds):
            // Idempotent: the daemon's subscribe replay can overlap a live event.
            guard sessions[session]?.windows.contains(where: { $0.windowID == windowID }) != true else { break }
            sessions[session]?.windows.append(ClaimedWindowState(windowID: windowID, app: app, title: title, bounds: bounds))
        case .windowReleased(let session, let windowID, _):
            sessions[session]?.windows.removeAll { $0.windowID == windowID }
            frames.removeValue(forKey: windowID)
        case .action(_, let windowID, let kind, let x, let y):
            lastAction = (windowID, kind, x, y, Date())
        case .screenshotTaken(_, let windowID, let pngBase64, _, _, _):
            if let data = Data(base64Encoded: pngBase64) { frames[windowID] = data }
        case .statusChanged(let session, let status):
            sessions[session]?.status = status
        case .permissions(let screenRecording, let accessibility):
            permissions = (screenRecording, accessibility)
        case .stopped(_, let session):
            if let session {
                // Per-session stop: drop just that session.
                if let ended = sessions.removeValue(forKey: session) {
                    for window in ended.windows { frames.removeValue(forKey: window.windowID) }
                }
            } else {
                sessions.removeAll()
                frames.removeAll()
                lastAction = nil
            }
        }
        onEvent?(event)
    }
}

/// NSLock behind a sync `with` — legal from async contexts, where Swift 6
/// forbids bare lock()/unlock(). Never call async or reenter inside `body`.
private final class Locked<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) { self.value = value }

    func with<R>(_ body: (inout Value) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
