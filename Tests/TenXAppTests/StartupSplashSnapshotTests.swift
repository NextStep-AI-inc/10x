import SwiftUI
import Testing
@testable import TenXApp

@MainActor
@Test func startupSplashLoadingSnapshot() throws {
    let state = StartupState()
    let attempt = UUID()
    state.beginAttempt(id: attempt)
    state.markLoading(.runtime, attemptID: attempt)
    state.markReady(.runtime, attemptID: attempt)
    state.markLoading(.sessions, attemptID: attempt)

    try assertSnapshot(
        SplashView(
            presentation: SplashPresentation.startup(
                state: state, onRetry: {}, onContinue: {}),
            buildVersion: "0.1.0")
            .environment(\.startupSignalReduceMotionOverride, true),
        name: "startup-splash-loading",
        size: CGSize(width: 640, height: 400))
}

@MainActor
@Test func startupSplashRecoverySnapshot() throws {
    let state = StartupState()
    let attempt = UUID()
    state.beginAttempt(id: attempt)
    state.markReady(.runtime, attemptID: attempt)
    state.markReady(.sessions, attemptID: attempt)
    state.markLoading(.recentProjects, attemptID: attempt)
    state.enterRecovery(attemptID: attempt)

    try assertSnapshot(
        SplashView(
            presentation: SplashPresentation.startup(
                state: state, onRetry: {}, onContinue: {}),
            buildVersion: "0.1.0")
            .environment(\.startupSignalReduceMotionOverride, true),
        name: "startup-splash-recovery",
        size: CGSize(width: 640, height: 400))
}

// MARK: - Dark appearance mirrors
//
// Generated from the light fixtures in this file so the two stay in step:
// same view, same state, host pinned to .darkAqua. These are the catalog of
// what dark mode looks like, and the net for a token that no contrast
// assertion can see is wrong.

@MainActor
@Test func startupSplashLoadingSnapshotDark() throws {
    let state = StartupState()
    let attempt = UUID()
    state.beginAttempt(id: attempt)
    state.markLoading(.runtime, attemptID: attempt)
    state.markReady(.runtime, attemptID: attempt)
    state.markLoading(.sessions, attemptID: attempt)

    try assertSnapshot(
        SplashView(
            presentation: SplashPresentation.startup(
                state: state, onRetry: {}, onContinue: {}),
            buildVersion: "0.1.0")
            .environment(\.startupSignalReduceMotionOverride, true),
        name: "startup-splash-loading-dark", appearance: .dark,
        size: CGSize(width: 640, height: 400))
}
