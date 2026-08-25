import Foundation
import OmpKit
import Testing
@testable import TenXApp

@MainActor @Test func contextPercentageIsClampedToItsDisplayRange() {
    #expect(SessionController.contextPercent(.object(["percentage": .double(210)])) == 100)
    #expect(SessionController.contextPercent(.object(["percentage": .double(-0.2)])) == 0)
    #expect(SessionController.contextPercent(.object(["percentage": .double(0.63)])) == 63)
}

@MainActor @Test func providerIDReadsOnlyANonemptyProviderFromAModelObject() {
    #expect(SessionController.providerID(from: .object([
        "id": .string("claude-sonnet"),
        "provider": .string("anthropic"),
    ])) == "anthropic")
    #expect(SessionController.providerID(from: .string("claude-sonnet")) == nil)
    #expect(SessionController.providerID(from: nil) == nil)
}

@MainActor @Test func unexpectedExitPreservesDraftAndOffersRecovery() {
    let registry = SessionActivityRegistry()
    let id = UUID()
    let controller = SessionController(
        processManager: SessionProcessManager(),
        id: id,
        activityRegistry: registry)
    controller.draft = "Unsent follow-up"
    registry.update(sessionID: id, providerID: "anthropic", isGenerating: true)

    controller.handleUnexpectedExit(code: 9, stderrTail: "process terminated")

    #expect(controller.runtimeState == .stopped(code: 9, stderrTail: "process terminated"))
    #expect(controller.draft == "Unsent follow-up")
    #expect(controller.isRecoveryPresented)
    #expect(controller.logText == "process terminated")
    #expect(registry.activeCounts.isEmpty)
}

@MainActor @Test func stoppingActivityTrackingRemovesTheControllerEntry() {
    let registry = SessionActivityRegistry()
    let id = UUID()
    let controller = SessionController(
        processManager: SessionProcessManager(),
        id: id,
        activityRegistry: registry)
    registry.update(sessionID: id, providerID: "anthropic", isGenerating: true)

    controller.stopActivityTracking()

    #expect(registry.activeCounts.isEmpty)
}
