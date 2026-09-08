import CoreGraphics
import Foundation

public struct SessionID: Hashable, Sendable, CustomStringConvertible {
    public let raw: Int
    public init(raw: Int) { self.raw = raw }
    public var description: String { String(raw) }
}

public struct SessionInfo: Sendable, Equatable {
    public let id: SessionID
    public var harness: String
    public var status: String?
    public var isActive: Bool
}

/// Pure claim/session bookkeeping. Thread-safety lives in the daemon (Task 8);
/// this type is deliberately single-threaded value logic.
public final class SessionRegistry {
    public private(set) var sessions: [SessionID: SessionInfo] = [:]
    private var claims: [CGWindowID: SessionID] = [:]
    private var windows: [CGWindowID: WindowInfo] = [:]
    private var nextRawID = 0

    public init() {}

    @discardableResult
    public func registerSession(clientName: String?) -> SessionID {
        nextRawID += 1
        let id = SessionID(raw: nextRawID)
        sessions[id] = SessionInfo(id: id, harness: clientName ?? "unknown", status: nil, isActive: true)
        return id
    }

    public func session(_ id: SessionID) -> SessionInfo? { sessions[id] }

    public func isActive(_ id: SessionID) -> Bool { sessions[id]?.isActive ?? false }

    public func claim(_ window: WindowInfo, for session: SessionID) throws {
        guard isActive(session) else { throw ComputerError("session_stopped") }
        if let owner = claims[window.id] {
            if owner == session { return }
            let ownerInfo = sessions[owner]
            throw ComputerError("already_claimed: window owned by session \(owner) (\(ownerInfo?.harness ?? "unknown"))")
        }
        claims[window.id] = session
        windows[window.id] = window
    }

    public func owner(of windowID: CGWindowID) -> SessionID? { claims[windowID] }

    public func window(_ windowID: CGWindowID) -> WindowInfo? { windows[windowID] }

    public func claimedWindows(for session: SessionID) -> [WindowInfo] {
        claims.filter { $0.value == session }.compactMap { windows[$0.key] }
    }

    public func setStatus(_ status: String?, for session: SessionID) {
        sessions[session]?.status = status
    }

    public func setHarness(_ harness: String, for session: SessionID) {
        sessions[session]?.harness = harness
    }

    @discardableResult
    public func release(_ windowID: CGWindowID) -> Bool {
        claims.removeValue(forKey: windowID) != nil
    }

    public func releaseAll(for session: SessionID) {
        for (windowID, owner) in claims where owner == session {
            claims.removeValue(forKey: windowID)
        }
    }

    public func windowClosed(_ windowID: CGWindowID) {
        claims.removeValue(forKey: windowID)
        windows.removeValue(forKey: windowID)
    }

    public func stop(_ session: SessionID) {
        releaseAll(for: session)
        sessions[session]?.isActive = false
    }

    public func stopAll() {
        claims.removeAll()
        for id in sessions.keys { sessions[id]?.isActive = false }
    }
}
