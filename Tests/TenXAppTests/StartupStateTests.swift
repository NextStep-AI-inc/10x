import Foundation
import Testing
@testable import TenXApp

@Test func liveStartupTimingKeepsSplashVisibleForAtLeastOneSecond() async throws {
    let clock = ContinuousClock()
    let start = clock.now

    try await StartupTiming.live.sleep(StartupTiming.live.minimumVisibility)

    #expect(start.duration(to: clock.now) >= .seconds(1))
}

@MainActor
@Test func startupRowsUseTheApprovedOrderAndExactCopy() {
    let state = StartupState()

    #expect(state.rows.map(\.id) == [
        .runtime,
        .sessions,
        .settings,
        .recentProjects,
    ])
    #expect(state.rows.map(\.title) == [
        "Preparing runtime",
        "Loading sessions",
        "Loading settings",
        "Preparing recent projects",
    ])
    #expect(StartupState.buildLabel(version: "0.1.0") == "BUILD 0.1.0")
    #expect(!StartupState.buildLabel(version: "0.1.0").contains("10x"))
}

@MainActor
@Test func recoveryPreservesReadyRowsAndStopsOnlyUnfinishedRows() {
    let state = StartupState()
    let attempt = UUID()
    state.beginAttempt(id: attempt)
    state.markLoading(.runtime, attemptID: attempt)
    state.markReady(.runtime, attemptID: attempt)
    state.markLoading(.sessions, attemptID: attempt)

    state.enterRecovery(attemptID: attempt)

    #expect(state.phase == .recovery)
    #expect(state.status(of: .runtime) == .ready)
    #expect(state.status(of: .sessions) == .stopped)
    #expect(state.status(of: .settings) == .stopped)
    #expect(state.footerTitle == "Startup needs attention")
    #expect(state.footerDetail == "Retry the stopped work or continue with what is ready.")
    #expect(!state.isSignalAnimating)
}

@MainActor
@Test func retryReturnsOnlyStoppedStagesAndIgnoresLateAttempts() {
    let state = StartupState()
    let first = UUID()
    state.beginAttempt(id: first)
    state.markReady(.runtime, attemptID: first)
    state.enterRecovery(attemptID: first)
    let retry = UUID()

    let stages = state.beginRetry(id: retry)
    state.markReady(.sessions, attemptID: first)

    #expect(stages == [.sessions, .settings, .recentProjects])
    #expect(state.status(of: .runtime) == .ready)
    #expect(state.status(of: .sessions) == .queued)
}

@MainActor
@Test func handoffGenerationAdvancesOnlyOncePerAttempt() {
    let state = StartupState()
    let attempt = UUID()
    state.beginAttempt(id: attempt)
    state.requestHandoff(attemptID: attempt)
    state.requestHandoff(attemptID: attempt)

    #expect(state.phase == .handoff)
    #expect(state.handoffGeneration == 1)
}

@MainActor
@Test func footerUsesTheFirstLoadingStageInLedgerOrder() {
    let state = StartupState()
    let attempt = UUID()
    state.beginAttempt(id: attempt)
    state.markLoading(.settings, attemptID: attempt)
    state.markLoading(.sessions, attemptID: attempt)

    #expect(state.footerTitle == "Loading sessions")
    #expect(state.footerDetail == "Indexing active and archived sessions")
}

@MainActor
@Test func invalidatedReadyStageBecomesRetryable() {
    let state = StartupState()
    let attempt = UUID()
    state.beginAttempt(id: attempt)
    for stage in StartupStageID.allCases {
        state.markReady(stage, attemptID: attempt)
    }

    state.markStopped(.recentProjects, attemptID: attempt)
    state.enterRecovery(attemptID: attempt)

    #expect(state.status(of: .recentProjects) == .stopped)
    #expect(state.beginRetry(id: UUID()) == [.recentProjects])
}
