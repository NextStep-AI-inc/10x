import ComputerKit
import Foundation
import Observation

/// Per-session computer-use state, derived from the session's own MCP tool
/// stream plus the shared daemon supervision feed. The daemon owns claims and
/// exclusivity; this controller is chrome + the stop button.
@MainActor
@Observable
final class ComputerUseController {
    private(set) var phase: ComputerActivityPhase = .off
    private(set) var claimedWindowIDs: Set<Int> = []
    private(set) var status: String?
    private(set) var daemonSessionID: Int?

    private var tracker = ComputerActivityTracker()
    private let supervision: SupervisionClient

    init(supervision: SupervisionClient) {
        self.supervision = supervision
    }

    var isEnabled: Bool { phase != .off }

    /// The one window the header/popover talk about: the correlated daemon
    /// session's most recent claim, else this session's highest claimed id.
    /// Frame and label both derive from this so they can never disagree.
    private var focusWindowID: Int? {
        if let daemonSessionID,
           let window = supervision.sessions[daemonSessionID]?.windows.last(where: { claimedWindowIDs.contains($0.windowID) }) {
            return window.windowID
        }
        return claimedWindowIDs.sorted().last
    }

    /// Latest preview frame for the focus window.
    var latestFrame: Data? {
        focusWindowID.flatMap { supervision.frames[$0] }
    }

    /// "App — Title" for the focus window, from the supervision snapshot.
    var focusWindowLabel: String? {
        guard let focusWindowID else { return nil }
        guard let window = supervision.sessions.values
            .flatMap(\.windows)
            .first(where: { $0.windowID == focusWindowID }) else { return nil }
        return window.title.isEmpty ? window.app : "\(window.app) — \(window.title)"
    }

    // MARK: - Transcript stream (called by SessionController)

    func handleToolStarted(name: String, input: [String: Any]?) {
        tracker.toolStarted(name: name, input: input)
        sync()
    }

    func handleToolCompleted(name: String, claimedWindowID: Int? = nil) {
        tracker.toolCompleted(name: name, claimedWindowID: claimedWindowID)
        sync()
    }

    // MARK: - Supervision feed (forwarded from AppModel's subscription)

    func applySupervision(_ event: SupervisionEvent) {
        switch event {
        case .windowClaimed(let session, _, let windowID, _, _, _):
            if claimedWindowIDs.contains(windowID) { daemonSessionID = session }
        case .statusChanged(let session, let status) where session == daemonSessionID:
            self.status = status
        case .windowReleased(_, let windowID, _):
            if let id = claimedWindowIDs.first(where: { $0 == windowID }) {
                tracker.toolStarted(
                    name: "mcp__tenx-computer_computer_release",
                    input: ["window_id": id])
            }
        case .stopped(_, let session) where session == nil || session == daemonSessionID:
            tracker = ComputerActivityTracker()
            status = nil
            daemonSessionID = nil
        default:
            break
        }
        sync()
    }

    // MARK: - Stop

    func stopComputerUse() async {
        // Resolve at stop time from the shared snapshot: daemonSessionID is
        // only set by a live windowClaimed, which background sessions and
        // late attachers never see — their Stop must still reach the daemon.
        let target = daemonSessionID ?? supervision.sessions.first(where: { _, session in
            session.windows.contains { claimedWindowIDs.contains($0.windowID) }
        })?.key
        if let target { await supervision.stopSession(target) }
        tracker = ComputerActivityTracker()
        status = nil
        self.daemonSessionID = nil
        sync()
    }

    private func sync() {
        phase = tracker.phase
        claimedWindowIDs = tracker.claimedWindowIDs
    }
}
