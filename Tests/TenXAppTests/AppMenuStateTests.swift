import OmpKit
import Testing
@testable import TenXApp

@Test func menuStateDisablesWorkspaceCommandsDuringOnboardingOrMutation() {
    let session = menuMetadata("/sessions/current.jsonl")

    let onboarding = AppMenuState(
        route: .onboarding(.installOmp),
        sessions: [session],
        activeSessionPath: session.path,
        runtimeState: .streaming,
        isSessionMutationInFlight: false)
    let mutating = AppMenuState(
        route: .session(session.path),
        sessions: [session],
        activeSessionPath: session.path,
        runtimeState: .streaming,
        isSessionMutationInFlight: true)

    #expect(!onboarding.isWorkspaceAvailable)
    #expect(!onboarding.canStopResponse)
    #expect(!onboarding.canChooseMessageBehavior)
    #expect(!onboarding.canArchiveSession)
    #expect(!mutating.isWorkspaceAvailable)
    #expect(!mutating.canStopResponse)
    #expect(!mutating.canChooseMessageBehavior)
    #expect(!mutating.canArchiveSession)
}

@Test func menuStateNavigatesNewestFirstWithoutWrapping() {
    let newest = menuMetadata("/sessions/newest.jsonl")
    let middle = menuMetadata("/sessions/middle.jsonl")
    let oldest = menuMetadata("/sessions/oldest.jsonl")
    let sessions = [newest, middle, oldest]

    let middleState = AppMenuState(
        route: .session(middle.path),
        sessions: sessions,
        activeSessionPath: middle.path,
        runtimeState: .idle,
        isSessionMutationInFlight: false)
    let newestState = AppMenuState(
        route: .session(newest.path),
        sessions: sessions,
        activeSessionPath: newest.path,
        runtimeState: .idle,
        isSessionMutationInFlight: false)
    let oldestState = AppMenuState(
        route: .session(oldest.path),
        sessions: sessions,
        activeSessionPath: oldest.path,
        runtimeState: .idle,
        isSessionMutationInFlight: false)

    #expect(middleState.previousSession?.path == newest.path)
    #expect(middleState.nextSession?.path == oldest.path)
    #expect(newestState.previousSession == nil)
    #expect(newestState.nextSession?.path == middle.path)
    #expect(oldestState.previousSession?.path == middle.path)
    #expect(oldestState.nextSession == nil)
}

@Test func menuStateUsesTheResolvedActivePathForNewSessions() {
    let session = menuMetadata("/sessions/resolved.jsonl")

    let state = AppMenuState(
        route: .session("new:placeholder"),
        sessions: [session],
        activeSessionPath: session.path,
        runtimeState: .streaming,
        isSessionMutationInFlight: false)

    #expect(state.currentSessionPath == session.path)
    #expect(state.canStopResponse)
    #expect(state.canChooseMessageBehavior)
    #expect(state.canArchiveSession)
}

private func menuMetadata(_ path: String) -> SessionMetadata {
    SessionMetadata(
        path: path,
        sessionId: path,
        cwd: "/tmp/Project",
        title: "Session",
        created: .distantPast,
        modified: .distantPast,
        sizeBytes: 10,
        status: .complete)
}
