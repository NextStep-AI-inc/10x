import CoreGraphics
import Foundation
import Testing
@testable import TenXApp

@Test func flyerOverlayReservesTranscriptAndJumpClearance() {
    let oneMeasuredRow: CGFloat = 34
    let threeMeasuredRows: CGFloat = 118

    #expect(TranscriptView.resolvedBottomOverlayClearance(0) == 0)
    #expect(TranscriptView.resolvedBottomOverlayClearance(oneMeasuredRow) == oneMeasuredRow)
    #expect(TranscriptView.resolvedBottomOverlayClearance(threeMeasuredRows) == threeMeasuredRows)
    #expect(TranscriptView.jumpToLatestBottomPadding(oneMeasuredRow) == oneMeasuredRow + 12)
    #expect(TranscriptView.jumpToLatestBottomPadding(threeMeasuredRows) == threeMeasuredRows + 12)
}

@MainActor
@Test func flyerFixtureRoutesSeedCanonicalSessionAndGlobalRows() throws {
    let routes: [(UIFixtureRoute, Int)] = [
        (.flyerFitting, 1),
        (.flyerOverflow, 1),
        (.flyerStack, 3),
        (.flyerRecovery, 3),
    ]

    for (route, expectedCount) in routes {
        let configuration = try flyerFixtureConfiguration(route)
        guard case .session(let sessionPath) = configuration.model.route else {
            Issue.record("Fixture did not select its canonical session path")
            continue
        }
        #expect(configuration.model.flyerCenter.visible(
            sessionKey: sessionPath,
            at: Date()).count == expectedCount)
        #expect(configuration.model.flyerCenter.visible(
            sessionKey: "another-session",
            at: Date()).count == (expectedCount == 3 ? 1 : 0))
        #expect(configuration.model.composerControls != nil)
        #expect(configuration.model.composerCommands != nil)
        if route == .flyerRecovery {
            #expect(configuration.model.activeSession?.isRecoveryPresented == true)
        }
    }
}

@MainActor
@Test func flyerActionsRunBeforeRemovalAndCanReplaceAnotherRow() throws {
    let replacementConfiguration = try flyerFixtureConfiguration(.flyerStack)
    let replacementModel = replacementConfiguration.model
    guard case .session(let sessionPath) = replacementModel.route else {
        Issue.record("Fixture did not select its canonical session path")
        return
    }
    let actionRow = try #require(replacementModel.flyerCenter.visible(
        sessionKey: sessionPath,
        at: Date()).first { $0.id == "session-attention" })

    replacementModel.performFlyerAction(actionRow.key, actionID: "replace-global")

    let visible = replacementModel.flyerCenter.visible(sessionKey: sessionPath, at: Date())
    #expect(!visible.contains { $0.key == actionRow.key })
    #expect(visible.first { $0.id == "global" }?.detail
        == "The global fixture notice was replaced in place.")

    let expiryConfiguration = try flyerFixtureConfiguration(.flyerStack)
    let expiryModel = expiryConfiguration.model
    guard case .session(let expirySessionPath) = expiryModel.route else {
        Issue.record("Expiry fixture did not select its canonical session path")
        return
    }
    let expiryActionRow = try #require(expiryModel.flyerCenter.visible(
        sessionKey: expirySessionPath,
        at: Date()).first { $0.id == "session-expiry" })
    let actionDate = Date()

    expiryModel.performFlyerAction(expiryActionRow.key, actionID: "expire-fixture")

    let scheduledExpiry = try #require(expiryModel.flyerCenter.visible(
        sessionKey: expirySessionPath,
        at: actionDate).first { $0.id == "expired-result" })
    let expiresAt = try #require(scheduledExpiry.expiresAt)
    #expect(expiresAt > actionDate)
    #expect(expiresAt.timeIntervalSince(actionDate) <= 2.1)
    #expect(!expiryModel.flyerCenter.visible(
        sessionKey: expirySessionPath,
        at: expiresAt).contains { $0.key == scheduledExpiry.key })
}

@MainActor
@Test func flyerIntegrationSnapshotCandidates() async throws {
    let stack = try flyerFixtureConfiguration(.flyerStack)
    await stack.model.prepareFlyerComposerFixture()
    try assertSnapshot(
        FlyerFixtureScene(configuration: stack),
        name: "flyer-overlay-shell",
        size: CGSize(width: 1_440, height: 900))

    let recovery = try flyerFixtureConfiguration(.flyerRecovery)
    await recovery.model.prepareFlyerComposerFixture()
    try assertSnapshot(
        FlyerFixtureScene(configuration: recovery),
        name: "flyer-recovery-shell-dark",
        appearance: .dark,
        size: CGSize(width: 760, height: 560))
}

@MainActor
private func flyerFixtureConfiguration(
    _ route: UIFixtureRoute
) throws -> SessionMapFixtureScene.Configuration {
    try SessionMapFixtureScene.make(
        route: route,
        environment: [
            UIFixtureRoute.environmentKey: route.rawValue,
            "TENX_UI_FIXTURE_SHA": "task-four-integration",
            "TENX_UI_FIXTURE_APPEARANCE": route == .flyerRecovery ? "dark" : "light",
            "TENX_UI_FIXTURE_REDUCE_MOTION": "on",
            "TENX_UI_FIXTURE_REDUCE_TRANSPARENCY": route == .flyerRecovery ? "on" : "off",
        ],
        isolatedRootOverride: FileManager.default.temporaryDirectory
            .appending(path: "10x-flyer-integration-\(route.rawValue)", directoryHint: .isDirectory))
}
