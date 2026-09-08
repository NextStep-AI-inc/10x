import ComputerKit
import CoreGraphics
import Foundation

struct OverlayState: Equatable {
    var app: String
    var frame: CGRect
    var status: String?
    var cursor: CGPoint?
    var cursorKind: String?
    var cursorAt: Date?
}

/// Pure reducer behind the on-screen overlay. One state per claimed window.
@Observable
final class OverlayModel {
    private(set) var overlays: [Int: OverlayState] = [:] // windowID -> state
    private var sessionStatus: [Int: String] = [:]
    private var windowSession: [Int: Int] = [:]

    func apply(_ event: SupervisionEvent) {
        switch event {
        case .windowClaimed(let session, _, let windowID, let app, _, let bounds):
            windowSession[windowID] = session
            overlays[windowID] = OverlayState(
                app: app,
                frame: Self.parseBounds(bounds) ?? .zero,
                status: sessionStatus[session],
                cursor: nil, cursorKind: nil, cursorAt: nil)
        case .windowReleased(_, let windowID, _):
            overlays.removeValue(forKey: windowID)
            windowSession.removeValue(forKey: windowID)
        case .action(_, let windowID, let kind, let x, let y):
            // type/key carry null coordinates — the cursor stays put.
            guard overlays[windowID] != nil, let x, let y else { return }
            overlays[windowID]?.cursor = CGPoint(x: x, y: y)
            overlays[windowID]?.cursorKind = kind
            overlays[windowID]?.cursorAt = Date()
        case .statusChanged(let session, let status):
            sessionStatus[session] = status
            for (windowID, owner) in windowSession where owner == session {
                overlays[windowID]?.status = status
            }
        case .sessionEnded(let session, _):
            for (windowID, owner) in windowSession where owner == session {
                overlays.removeValue(forKey: windowID)
                windowSession.removeValue(forKey: windowID)
            }
            sessionStatus.removeValue(forKey: session)
        case .stopped:
            overlays.removeAll()
            windowSession.removeAll()
            sessionStatus.removeAll()
        default:
            break
        }
    }

    /// Reposition overlays as windows move (called on a 0.5s timer).
    func pollBounds(_ boundsProvider: (Int) -> CGRect?) {
        for windowID in overlays.keys {
            if let bounds = boundsProvider(windowID) {
                overlays[windowID]?.frame = bounds
            } else {
                overlays.removeValue(forKey: windowID) // window closed
                windowSession.removeValue(forKey: windowID)
            }
        }
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
