import ComputerKit
import CoreGraphics
import Foundation

struct OverlayState: Equatable {
    /// System-owned tag identity: "Harness · session label", falling back to
    /// the claimed window's app name when the session set no label.
    var identity: String
    var frame: CGRect // Quartz top-left screen coords, as reported by CGWindowList
    var status: String?
    var cursor: CGPoint?
    var cursorKind: String?
    var isOnscreen: Bool
}

/// Pure reducer behind the on-screen overlay. One state per claimed window.
@Observable
final class OverlayModel {
    private(set) var overlays: [Int: OverlayState] = [:] // windowID -> state
    private var sessionStatus: [Int: String] = [:]
    private var sessionIdentity: [Int: String] = [:]
    private var windowSession: [Int: Int] = [:]

    func apply(_ event: SupervisionEvent) {
        switch event {
        case .sessionStarted(let session, let harness, let label, _):
            sessionIdentity[session] = label.map { "\(harness) · \($0)" } ?? harness
        case .windowClaimed(let session, let harness, let windowID, let app, _, let bounds):
            windowSession[windowID] = session
            // No session label → fall back to the app name for readability.
            let identity = sessionIdentity[session] ?? (app.isEmpty ? harness : "\(harness) · \(app)")
            overlays[windowID] = OverlayState(
                identity: identity,
                frame: Self.parseBounds(bounds) ?? .zero,
                status: sessionStatus[session],
                cursor: nil, cursorKind: nil, isOnscreen: true)
        case .windowReleased(_, let windowID, _):
            overlays.removeValue(forKey: windowID)
            windowSession.removeValue(forKey: windowID)
        case .action(_, let windowID, let kind, let x, let y):
            // type/key carry null coordinates — the cursor stays put.
            guard overlays[windowID] != nil, let x, let y else { return }
            overlays[windowID]?.cursor = CGPoint(x: x, y: y)
            overlays[windowID]?.cursorKind = kind
        case .statusChanged(let session, let status):
            sessionStatus[session] = status
            for (windowID, owner) in windowSession where owner == session {
                overlays[windowID]?.status = status
            }
        case .sessionEnded(let session, _):
            removeSession(session)
        case .stopped(_, let session):
            // nil = global shut-off; otherwise only that session's overlays.
            if let session { removeSession(session) } else { removeAll() }
        default:
            break
        }
    }

    /// Reposition overlays as windows move (called on a 0.5s timer).
    /// Provider returns nil when the window is gone, otherwise the current
    /// Quartz bounds plus whether the window is onscreen (minimized or
    /// another Space → overlay hides but survives).
    func pollBounds(_ boundsProvider: (Int) -> (CGRect, Bool)?) {
        for windowID in Array(overlays.keys) {
            if let (bounds, isOnscreen) = boundsProvider(windowID) {
                overlays[windowID]?.frame = bounds
                overlays[windowID]?.isOnscreen = isOnscreen
            } else {
                // ponytail: screen-recording revocation also yields "gone" —
                // the overlay returns on the next claim. Ceiling noted.
                overlays.removeValue(forKey: windowID)
                windowSession.removeValue(forKey: windowID)
            }
        }
    }

    func removeAll() {
        overlays.removeAll()
        windowSession.removeAll()
        sessionStatus.removeAll()
        sessionIdentity.removeAll()
    }

    private func removeSession(_ session: Int) {
        for (windowID, owner) in windowSession where owner == session {
            overlays.removeValue(forKey: windowID)
            windowSession.removeValue(forKey: windowID)
        }
        sessionStatus.removeValue(forKey: session)
        sessionIdentity.removeValue(forKey: session)
    }

    static func parseBounds(_ string: String) -> CGRect? {
        // "x,y WxH"
        let parts = string.split(separator: " ")
        guard parts.count == 2 else { return nil }
        let origin = parts[0].split(separator: ",").compactMap { Double($0) }
        let size = parts[1].split(separator: "x").compactMap { Double($0) }
        guard origin.count == 2, size.count == 2 else { return nil }
        return CGRect(x: origin[0], y: origin[1], width: size[0], height: size[1])
    }
}
