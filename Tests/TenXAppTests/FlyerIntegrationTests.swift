import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import TenXApp

@MainActor
@Test func flyerOverlayReservesTranscriptAndJumpClearance() throws {
    let zero = try renderedFlyerLayout(route: .flyerFitting, flyerCount: 0)
    let one = try renderedFlyerLayout(route: .flyerFitting, flyerCount: 1)
    let three = try renderedFlyerLayout(route: .flyerStack, flyerCount: 3)

    #expect(zero.clearanceFrame.height == 0)
    #expect(abs(zero.transcriptFrame.maxY - zero.jumpFrame.maxY - 12) < 0.5)
    #expect(one.stackFrame.height > 0)
    #expect(abs(one.clearanceFrame.height - one.stackFrame.height) < 0.5)
    #expect(abs(one.stackFrame.minY - one.jumpFrame.maxY - 12) < 0.5)
    #expect(three.stackFrame.height > one.stackFrame.height)
    #expect(abs(three.clearanceFrame.height - three.stackFrame.height) < 0.5)
    #expect(abs(three.stackFrame.minY - three.jumpFrame.maxY - 12) < 0.5)
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
@Test func flyerActionsPreserveSameKeyGlobalAndSessionReplacements() throws {
    let replacementConfiguration = try flyerFixtureConfiguration(.flyerStack)
    let replacementModel = replacementConfiguration.model
    guard case .session(let sessionPath) = replacementModel.route else {
        Issue.record("Fixture did not select its canonical session path")
        return
    }
    let initialRows = replacementModel.flyerCenter.visible(sessionKey: sessionPath, at: Date())
    let globalRow = try #require(initialRows.first { $0.id == "global" })
    let sessionRow = try #require(initialRows.first { $0.id == "session-attention" })
    let globalIndex = try #require(initialRows.firstIndex { $0.key == globalRow.key })
    let sessionIndex = try #require(initialRows.firstIndex { $0.key == sessionRow.key })

    replacementModel.performFlyerAction(globalRow.key, actionID: "replace-global")
    replacementModel.performFlyerAction(sessionRow.key, actionID: "replace-session")

    let visible = replacementModel.flyerCenter.visible(sessionKey: sessionPath, at: Date())
    try #require(visible.count == initialRows.count)
    #expect(visible[globalIndex].key == globalRow.key)
    #expect(visible[globalIndex].detail
        == "The global fixture notice was replaced in place.")
    #expect(visible[sessionIndex].key == sessionRow.key)
    #expect(visible[sessionIndex].scope == .session(sessionPath))
    #expect(visible[sessionIndex].detail
        == "The session fixture notice was replaced in place.")

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

@MainActor
private func renderedFlyerLayout(
    route: UIFixtureRoute,
    flyerCount: Int
) throws -> FlyerOverlayLayoutProbe {
    let configuration = try flyerFixtureConfiguration(route)
    guard case .session(let sessionPath) = configuration.model.route,
          let controller = configuration.model.activeSession else {
        throw FlyerLayoutTestError.missingSession
    }
    if flyerCount == 0 {
        for flyer in configuration.model.flyerCenter.visible(sessionKey: sessionPath, at: Date()) {
            configuration.model.flyerCenter.remove(flyer.key)
        }
    }
    controller.viewport.isFollowingLatest = false
    let probe = FlyerOverlayLayoutProbe(expectsStack: flyerCount > 0)
    let root = FlyerFixtureScene(configuration: configuration)
        .environment(\.flyerOverlayLayoutObserver, probe.record)
        .frame(width: 1_440, height: 900)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    let host = NSHostingView(rootView: root)
    host.appearance = NSAppearance(named: .aqua)
    host.frame = CGRect(x: 0, y: 0, width: 1_440, height: 900)

    let deadline = Date().addingTimeInterval(1)
    repeat {
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        if probe.isComplete { break }
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    } while Date() < deadline

    try probe.requireComplete()
    return probe
}

@MainActor
private final class FlyerOverlayLayoutProbe {
    private let expectsStack: Bool
    private(set) var stackFrame: CGRect = .zero
    private(set) var transcriptFrame: CGRect = .zero
    private(set) var clearanceFrame: CGRect = .null
    private(set) var jumpFrame: CGRect = .zero

    init(expectsStack: Bool) {
        self.expectsStack = expectsStack
    }

    func record(_ event: FlyerOverlayLayoutEvent) {
        switch event {
        case .stackFrame(let frame): stackFrame = frame
        case .transcriptFrame(let frame): transcriptFrame = frame
        case .clearanceFrame(let frame): clearanceFrame = frame
        case .jumpFrame(let frame): jumpFrame = frame
        }
    }

    var isComplete: Bool {
        transcriptFrame.height > 0
            && !clearanceFrame.isNull
            && jumpFrame.height > 0
            && (!expectsStack || stackFrame.height > 0)
    }

    func requireComplete() throws {
        guard isComplete else { throw FlyerLayoutTestError.incompleteGeometry }
    }
}

private enum FlyerLayoutTestError: Error {
    case missingSession
    case incompleteGeometry
}
