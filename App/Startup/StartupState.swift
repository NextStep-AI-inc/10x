import Foundation
import Observation

enum StartupStageID: String, CaseIterable, Identifiable, Hashable, Sendable {
    case runtime
    case sessions
    case settings
    case recentProjects
    case updates

    var id: Self { self }

    var title: String {
        switch self {
        case .runtime: "Preparing runtime"
        case .sessions: "Loading sessions"
        case .settings: "Loading settings"
        case .recentProjects: "Preparing recent projects"
        case .updates: "Checking for updates"
        }
    }

    var detail: String {
        switch self {
        case .runtime: "Checking OMP and provider access"
        case .sessions: "Indexing active and archived sessions"
        case .settings: "Preparing your configuration"
        case .recentProjects: "Starting recent workspaces"
        case .updates: "Looking for a newer version"
        }
    }

    /// The stages that gate handoff and may enter recovery. `updates` is advisory and
    /// is deliberately absent: a check that fails must never stop a launch.
    static let gatingCases: [StartupStageID] = [
        .runtime, .sessions, .settings, .recentProjects,
    ]
}

enum StartupStageStatus: String, Equatable, Sendable {
    case queued = "Queued"
    case loading = "Loading"
    case ready = "Ready"
    case stopped = "Stopped"
}

enum StartupPhase: Equatable, Sendable {
    case preparing
    case recovery
    case handoff
}

struct StartupTiming: Sendable {
    let minimumVisibility: Duration
    let timeout: Duration
    let updateCheckDeadline: Duration
    /// How long a user-initiated (menu) update check waits for an answer before giving
    /// up. Deliberately its own value rather than reusing `updateCheckDeadline`: that
    /// deadline is sized to protect launch speed for an advisory check nobody asked for,
    /// while a menu check is something the user explicitly requested and is willing to
    /// wait longer on — reusing the 3-second launch deadline would surface spurious
    /// "Update failed" results for a menu check that was simply slow, not stuck.
    let menuUpdateCheckDeadline: Duration
    let sleep: @Sendable (Duration) async throws -> Void

    init(
        minimumVisibility: Duration,
        timeout: Duration,
        updateCheckDeadline: Duration,
        menuUpdateCheckDeadline: Duration = .seconds(15),
        sleep: @escaping @Sendable (Duration) async throws -> Void
    ) {
        self.minimumVisibility = minimumVisibility
        self.timeout = timeout
        self.updateCheckDeadline = updateCheckDeadline
        self.menuUpdateCheckDeadline = menuUpdateCheckDeadline
        self.sleep = sleep
    }

    static let live = StartupTiming(
        minimumVisibility: .milliseconds(1_200),
        timeout: .seconds(10),
        updateCheckDeadline: .seconds(3),
        menuUpdateCheckDeadline: .seconds(15),
        sleep: { duration in try await ContinuousClock().sleep(for: duration) })
}

@MainActor
@Observable
final class StartupState {
    private(set) var phase: StartupPhase = .preparing
    private(set) var handoffGeneration = 0
    private(set) var attemptID: UUID?
    private var statuses: [StartupStageID: StartupStageStatus] = Dictionary(
        uniqueKeysWithValues: StartupStageID.allCases.map { ($0, .queued) })
    private var openedWorkspaceGeneration = 0

    var rows: [SplashLedgerRow] {
        StartupStageID.allCases.map {
            SplashLedgerRow(
                id: $0.rawValue,
                title: $0.title,
                status: statuses[$0] ?? .queued)
        }
    }

    var footerTitle: String {
        phase == .recovery ? "Startup needs attention" : currentStage.title
    }

    var footerDetail: String {
        phase == .recovery
            ? "Retry the stopped work or continue with what is ready."
            : currentStage.detail
    }

    var isSignalAnimating: Bool { phase == .preparing }

    static func buildLabel(version: String) -> String { "BUILD \(version)" }

    func status(of stage: StartupStageID) -> StartupStageStatus {
        statuses[stage] ?? .queued
    }

    func beginAttempt(id: UUID) {
        guard phase != .handoff else { return }
        attemptID = id
        phase = .preparing
        statuses = Dictionary(
            uniqueKeysWithValues: StartupStageID.allCases.map { ($0, .queued) })
    }

    func beginRetry(id: UUID) -> Set<StartupStageID> {
        let stages = Set(StartupStageID.gatingCases.filter { status(of: $0) != .ready })
        attemptID = id
        phase = .preparing
        for stage in stages { statuses[stage] = .queued }
        return stages
    }

    func markLoading(_ stage: StartupStageID, attemptID: UUID) {
        guard self.attemptID == attemptID, phase == .preparing else { return }
        statuses[stage] = .loading
    }

    func markReady(_ stage: StartupStageID, attemptID: UUID) {
        guard self.attemptID == attemptID, phase == .preparing else { return }
        statuses[stage] = .ready
    }

    func markStopped(_ stage: StartupStageID, attemptID: UUID) {
        guard stage != .updates else { return }
        guard self.attemptID == attemptID, phase == .preparing else { return }
        statuses[stage] = .stopped
    }

    /// Resolves the advisory `.updates` row once its launch check finishes, regardless
    /// of `phase`. `markReady` is deliberately gated on `phase == .preparing` to protect
    /// the four gating stages while they can still be invalidated into `.stopped`. The
    /// advisory row has no such protection to give: it is excluded from `gatingCases`
    /// and `enterRecovery` never touches it (see `recoveryNeverStopsTheAdvisoryUpdateRow`
    /// in StartupStateTests), so if recovery begins while the check is still in flight,
    /// `markReady` would silently no-op forever and strand the row at `Loading` for the
    /// rest of the recovery phase. This is the only mutator the advisory check may call
    /// after `enterRecovery` has already run.
    func resolveAdvisoryCheck(attemptID: UUID) {
        guard self.attemptID == attemptID else { return }
        statuses[.updates] = .ready
    }

    func enterRecovery(attemptID: UUID) {
        guard self.attemptID == attemptID, phase != .handoff else { return }
        for stage in StartupStageID.gatingCases where status(of: stage) != .ready {
            statuses[stage] = .stopped
        }
        phase = .recovery
    }

    func requestHandoff(attemptID: UUID) {
        guard self.attemptID == attemptID, phase != .handoff else { return }
        phase = .handoff
        handoffGeneration += 1
    }

    /// Returns `true` at most once per handoff. The latch lives here rather than in the
    /// scene view because the startup window is recreated when it is reopened in update
    /// mode, which resets any view-local counter and would open a duplicate workspace.
    func consumeWorkspaceOpenRequest() -> Bool {
        guard handoffGeneration > openedWorkspaceGeneration else { return false }
        openedWorkspaceGeneration = handoffGeneration
        return true
    }

    private var currentStage: StartupStageID {
        StartupStageID.allCases.first { status(of: $0) == .loading }
            ?? StartupStageID.allCases.last(where: { status(of: $0) == .ready })
            ?? .runtime
    }
}
