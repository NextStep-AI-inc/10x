import CoreGraphics
import Foundation

public struct SessionID: Hashable, Sendable, CustomStringConvertible {
    public let raw: Int
    init(raw: Int) { self.raw = raw }
    public var description: String { String(raw) }
}

public struct SessionInfo: Sendable, Equatable {
    public let id: SessionID
    public var harness: String
    public var label: String?
    public var peerPID: Int32?
    public var status: String?
    public var isActive: Bool
}

/// Claim/session bookkeeping. Thread-safe via internal lock.
public final class SessionRegistry {
    private let lock = NSRecursiveLock()
    private var sessions: [SessionID: SessionInfo] = [:]
    private var claims: [CGWindowID: SessionID] = [:]
    private var windows: [CGWindowID: WindowInfo] = [:]
    private var nextRawID = 0

    public init() {}

    /// Locked snapshot for bulk readers (stop_all, resource listing).
    public var allSessions: [SessionID: SessionInfo] {
        lock.lock()
        defer { lock.unlock() }
        return sessions
    }

    @discardableResult
    public func registerSession(clientName: String?, label: String? = nil, peerPID: Int32? = nil) -> SessionID {
        lock.lock()
        defer { lock.unlock() }
        nextRawID += 1
        let id = SessionID(raw: nextRawID)
        sessions[id] = SessionInfo(id: id, harness: clientName ?? "unknown", label: label, peerPID: peerPID, status: nil, isActive: true)
        return id
    }

    public func session(_ id: SessionID) -> SessionInfo? {
        lock.lock()
        defer { lock.unlock() }
        return sessions[id]
    }

    public func isActive(_ id: SessionID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return sessions[id]?.isActive ?? false
    }

    public func claim(_ window: WindowInfo, for session: SessionID) throws {
        lock.lock()
        defer { lock.unlock() }
        guard sessions[session]?.isActive == true else { throw ComputerError("session_stopped") }
        if let owner = claims[window.id] {
            if owner == session { windows[window.id] = window; return }
            let ownerInfo = sessions[owner]
            throw ComputerError("already_claimed: window owned by session \(owner) (\(ownerInfo?.harness ?? "unknown"))")
        }
        claims[window.id] = session
        windows[window.id] = window
    }

    public func owner(of windowID: CGWindowID) -> SessionID? {
        lock.lock()
        defer { lock.unlock() }
        return claims[windowID]
    }

    /// Returns the last known snapshot; outlives claims until `windowClosed`.
    public func window(_ windowID: CGWindowID) -> WindowInfo? {
        lock.lock()
        defer { lock.unlock() }
        return windows[windowID]
    }

    public func claimedWindows(for session: SessionID) -> [WindowInfo] {
        lock.lock()
        defer { lock.unlock() }
        return claims.filter { $0.value == session }.compactMap { windows[$0.key] }
    }

    public func setStatus(_ status: String?, for session: SessionID) {
        lock.lock()
        defer { lock.unlock() }
        sessions[session]?.status = status
    }

    public func setHarness(_ harness: String, for session: SessionID) {
        lock.lock()
        defer { lock.unlock() }
        sessions[session]?.harness = harness
    }

    /// Drops the claim only; the window snapshot remains until `windowClosed`.
    @discardableResult
    public func release(_ windowID: CGWindowID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return claims.removeValue(forKey: windowID) != nil
    }

    public func releaseAll(for session: SessionID) {
        lock.lock()
        defer { lock.unlock() }
        claims = claims.filter { $0.value != session }
    }

    /// Removes claim and snapshot when the OS window is gone.
    public func windowClosed(_ windowID: CGWindowID) {
        lock.lock()
        defer { lock.unlock() }
        claims.removeValue(forKey: windowID)
        windows.removeValue(forKey: windowID)
    }

    public func stop(_ session: SessionID) {
        lock.lock()
        defer { lock.unlock() }
        claims = claims.filter { $0.value != session }
        sessions[session]?.isActive = false
    }

    public func stopAll() {
        lock.lock()
        defer { lock.unlock() }
        claims.removeAll()
        for id in sessions.keys { sessions[id]?.isActive = false }
    }

    /// Removes a session record entirely (disconnect path). Supervised stop keeps the tombstone.
    public func removeSession(_ session: SessionID) {
        lock.lock()
        defer { lock.unlock() }
        claims = claims.filter { $0.value != session }
        sessions.removeValue(forKey: session)
    }
}
