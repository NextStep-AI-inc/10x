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

    /// Latest preview frame for this session's most recently claimed window.
    var latestFrame: Data? {
        claimedWindowIDs.sorted().last.flatMap { supervision.frames[$0] }
    }

    /// App names for claimed windows, from the supervision snapshot.
    var windowAppNames: [String] {
        claimedWindowIDs.sorted().compactMap { windowID in
            supervision.sessions.values
                .flatMap(\.windows)
                .first(where: { $0.windowID == windowID })?
                .app
        }
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
        if let daemonSessionID { await supervision.stopSession(daemonSessionID) }
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
