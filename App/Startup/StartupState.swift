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
    let sleep: @Sendable (Duration) async throws -> Void

    static let live = StartupTiming(
        minimumVisibility: .milliseconds(1_200),
        timeout: .seconds(10),
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

    private var currentStage: StartupStageID {
        StartupStageID.allCases.first { status(of: $0) == .loading }
            ?? StartupStageID.allCases.last(where: { status(of: $0) == .ready })
            ?? .runtime
    }
}
