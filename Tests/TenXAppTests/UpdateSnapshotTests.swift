import SwiftUI
import Testing
@testable import TenXApp

@MainActor
private func updateSplash(_ state: UpdateState) -> some View {
    SplashView(
        presentation: SplashPresentation.update(
            state: state, onInstall: {}, onDismiss: {}, onRetry: {}),
        buildVersion: "0.1.0")
        .environment(\.startupSignalReduceMotionOverride, true)
}

@MainActor
@Test func updateAvailableSnapshot() throws {
    let state = UpdateState()
    state.beginCheck()
    state.showAvailable(newVersion: "0.2.0", currentVersion: "0.1.0")

    try assertSnapshot(
        updateSplash(state),
        name: "update-available",
        size: CGSize(width: 640, height: 400))
}

@MainActor
@Test func updateDownloadingSnapshot() throws {
    let state = UpdateState()
    state.beginDownload()
    state.setExpectedBytes(61_800_000)
    state.addReceivedBytes(18_200_000)

    try assertSnapshot(
        updateSplash(state),
        name: "update-downloading",
        size: CGSize(width: 640, height: 400))
}

@MainActor
@Test func updateFailedSnapshot() throws {
    let state = UpdateState()
    state.beginDownload()
    state.beginVerifying()
    state.fail(.verification)

    try assertSnapshot(
        updateSplash(state),
        name: "update-failed",
        size: CGSize(width: 640, height: 400))
}

// MARK: - Dark appearance mirrors
//
// Generated from the light fixtures in this file so the two stay in step:
// same view, same state, host pinned to .darkAqua. These are the catalog of
// what dark mode looks like, and the net for a token that no contrast
// assertion can see is wrong.

@MainActor
@Test func updateAvailableSnapshotDark() throws {
    let state = UpdateState()
    state.beginCheck()
    state.showAvailable(newVersion: "0.2.0", currentVersion: "0.1.0")

    try assertSnapshot(
        updateSplash(state),
        name: "update-available-dark", appearance: .dark,
        size: CGSize(width: 640, height: 400))
}
