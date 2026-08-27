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

    #expect(state.rows.map(\.id) == StartupStageID.allCases.map(\.rawValue))
    #expect(state.rows.map(\.title) == [
        "Preparing runtime",
        "Loading sessions",
        "Loading settings",
        "Preparing recent projects",
        "Checking for updates",
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

@MainActor
@Test func startupPresentationCarriesTheLedgerAndFooterUnchanged() {
    let state = StartupState()
    let attempt = UUID()
    state.beginAttempt(id: attempt)
    state.markLoading(.runtime, attemptID: attempt)

    let presentation = SplashPresentation.startup(
        state: state, onRetry: {}, onContinue: {})

    #expect(presentation.heading == "Preparing your workspace")
    #expect(presentation.accessibilityLabel == "Preparing your workspace")
    #expect(presentation.footerTitle == "Preparing runtime")
    #expect(presentation.footerDetail == "Checking OMP and provider access")
    #expect(presentation.footerTone == .working)
    #expect(presentation.signalProgress == nil)
    #expect(presentation.isSignalAnimating)
    #expect(presentation.actions.isEmpty)
}

@MainActor
@Test func startupRecoveryPresentationOffersRetryThenContinue() {
    let state = StartupState()
    let attempt = UUID()
    state.beginAttempt(id: attempt)
    state.enterRecovery(attemptID: attempt)

    let presentation = SplashPresentation.startup(
        state: state, onRetry: {}, onContinue: {})

    #expect(presentation.footerTitle == "Startup needs attention")
    #expect(presentation.footerTone == .failed)
    #expect(presentation.isSignalFailed)
    #expect(!presentation.isSignalAnimating)
    #expect(presentation.actions.map(\.title) == ["Retry", "Continue to workspace"])
    #expect(presentation.actions.map(\.kind) == [.primary, .secondary])
}

@MainActor
@Test func theLedgerEndsWithTheAdvisoryUpdateRow() {
    let state = StartupState()

    #expect(state.rows.map(\.title) == [
        "Preparing runtime",
        "Loading sessions",
        "Loading settings",
        "Preparing recent projects",
        "Checking for updates",
    ])
    #expect(StartupStageID.updates.detail == "Looking for a newer version")
}

@MainActor
@Test func onlyTheFourWorkStagesGateTheLaunch() {
    #expect(StartupStageID.gatingCases == [
        .runtime, .sessions, .settings, .recentProjects,
    ])
    #expect(!StartupStageID.gatingCases.contains(.updates))
}

@MainActor
@Test func recoveryNeverStopsTheAdvisoryUpdateRow() {
    let state = StartupState()
    let attempt = UUID()
    state.beginAttempt(id: attempt)
    state.markLoading(.updates, attemptID: attempt)
    state.markLoading(.sessions, attemptID: attempt)

    state.enterRecovery(attemptID: attempt)

    #expect(state.status(of: .sessions) == .stopped)
    #expect(state.status(of: .updates) != .stopped)
}

@MainActor
@Test func theAdvisoryRowCannotBeStoppedDirectly() {
    let state = StartupState()
    let attempt = UUID()
    state.beginAttempt(id: attempt)
    state.markLoading(.updates, attemptID: attempt)

    state.markStopped(.updates, attemptID: attempt)

    #expect(state.status(of: .updates) == .loading)
}

@MainActor
@Test func retryNeverReRunsTheAdvisoryRow() {
    let state = StartupState()
    let attempt = UUID()
    state.beginAttempt(id: attempt)
    state.markReady(.runtime, attemptID: attempt)
    state.enterRecovery(attemptID: attempt)

    let retried = state.beginRetry(id: UUID())

    #expect(!retried.contains(.updates))
    #expect(retried == [.sessions, .settings, .recentProjects])
}

@MainActor
@Test func aHandoffOpensTheWorkspaceExactlyOnce() {
    let state = StartupState()
    let attempt = UUID()
    state.beginAttempt(id: attempt)

    #expect(!state.consumeWorkspaceOpenRequest())

    state.requestHandoff(attemptID: attempt)

    #expect(state.consumeWorkspaceOpenRequest())
    #expect(!state.consumeWorkspaceOpenRequest())
    #expect(!state.consumeWorkspaceOpenRequest())
}
