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

@MainActor @Test func controllerReportsProviderAndRuntimeTransitionsFromRPCLifecycle() async throws {
    let container = URL(filePath: NSTemporaryDirectory())
        .appendingPathComponent("controller-activity-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: container) }
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    let executable = try makeNavigationExecutable(in: container, mode: "activity-lifecycle")
    let processManager = SessionProcessManager(executable: executable.path)
    let registry = SessionActivityRegistry()
    let controller = SessionController(
        processManager: processManager,
        id: UUID(),
        activityRegistry: registry)
    let metadata = SessionMetadata(
        path: "/tmp/fake.jsonl",
        sessionId: "fake-session",
        cwd: "/tmp",
        title: "Fixture",
        created: .distantPast,
        modified: .distantPast,
        sizeBytes: 0,
        status: .complete)

    await controller.openExisting(metadata)

    let hasInitialStreamingActivity = controller.providerID == "initial-provider"
        && controller.runtimeState == .streaming
        && registry.activeCounts == ["initial-provider": 1]
    #expect(hasInitialStreamingActivity)
    guard hasInitialStreamingActivity else {
        await processManager.closeAll()
        return
    }

    controller.draft = "First turn"
    await controller.sendPrompt()
    let receivedUpdatedProvider = await controllerStateReaches {
        controller.providerID == "updated-provider"
            && registry.activeCounts == ["updated-provider": 1]
    }
    #expect(receivedUpdatedProvider)
    let retainedProviderWithoutModel = await controllerStateReaches {
        controller.thinkingLevel == "Medium"
            && controller.providerID == "updated-provider"
            && registry.activeCounts == ["updated-provider": 1]
    }
    #expect(retainedProviderWithoutModel)

    controller.handleUnexpectedExit(code: 9, stderrTail: "fixture exit")
    #expect(registry.activeCounts.isEmpty)

    await controller.restart()
    let restartedWithStreamingActivity = await controllerStateReaches {
        controller.providerID == "initial-provider"
            && controller.runtimeState == .streaming
            && registry.activeCounts == ["initial-provider": 1]
    }
    #expect(restartedWithStreamingActivity)

    controller.draft = "Second turn"
    await controller.sendPrompt()
    let clearedProviderFromModel = await controllerStateReaches {
        controller.providerID == nil && registry.activeCounts.isEmpty
    }
    #expect(clearedProviderFromModel)
    let returnedToIdle = await controllerStateReaches {
        controller.runtimeState == .idle && registry.activeCounts.isEmpty
    }
    #expect(returnedToIdle)

    await processManager.closeAll()
}

@MainActor
private func controllerStateReaches(_ predicate: () -> Bool) async -> Bool {
    for _ in 0..<100 {
        if predicate() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return predicate()
}
