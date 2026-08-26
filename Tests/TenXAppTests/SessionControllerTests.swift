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

@MainActor @Test func controllerRejectsSnapshotFromReplacedProcessor() {
    let activeID = UUID()
    let accepted = TranscriptSnapshot(
        processorID: activeID,
        revision: 1,
        items: [],
        runtimeState: .idle)
    let rejected = TranscriptSnapshot(
        processorID: UUID(),
        revision: 2,
        items: [],
        runtimeState: .streaming)

    #expect(SessionController.accepts(snapshot: accepted, activeProcessorID: activeID))
    #expect(!SessionController.accepts(snapshot: rejected, activeProcessorID: activeID))
    #expect(!SessionController.accepts(snapshot: accepted, activeProcessorID: Optional<UUID>.none))
}

@MainActor @Test func initialHistorySnapshotPreservesCurrentState() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let sessionURL = directory.appending(path: "history.jsonl")
    try writeHistoryMessage("Persisted history", to: sessionURL)
    let manager = fakeManager(mode: "no-session-file")
    let controller = SessionController(processManager: manager)

    await controller.openExisting(metadata(
        path: sessionURL.path,
        cwd: directory.path,
        title: "Persisted title"))

    #expect(controller.title == "Persisted title")
    #expect(controller.runtimeState == .idle)
    #expect(controller.visibleText(for: "hist-message") == "Persisted history")
    await manager.closeAll()
}

@MainActor @Test func finalSnapshotPrecedesReconciliation() async throws {
    let manager = fakeManager(mode: "transcript-burst")
    let controller = SessionController(processManager: manager)

    await controller.openNew(projectURL: try temporaryDirectory())
    controller.draft = "burst"
    await controller.sendPrompt()

    #expect(await eventually {
        controller.visibleText(for: "burst-message")?.count == 1_000
            && controller.runtimeState == .idle
    })
    await manager.closeAll()
}

@MainActor @Test func staleReconciliationFailureCannotOverwriteNewerBoundary() async throws {
    let loader = DelayedHistoryLoader()
    let manager = fakeManager(mode: "reconciliation-double-boundary")
    let controller = SessionController(
        processManager: manager,
        historyLoader: { path in try await loader.load(path: path) })

    await controller.openNew(projectURL: try temporaryDirectory())
    controller.draft = "trigger boundaries"
    await controller.sendPrompt()

    #expect(await loader.waitForRequestCount(3))
    #expect(await loader.waitForDelayedFailureCompletion())

    #expect(await eventually {
        !controller.items.contains { $0.id == "reconciliation-warning" }
    })
    await manager.closeAll()
}

@MainActor @Test func staleBoundaryCannotCancelCurrentReconciliation() async throws {
    let loader = CurrentReconciliationLoader()
    let manager = fakeManager(mode: "basic")
    let controller = SessionController(
        processManager: manager,
        historyLoader: { path in try await loader.load(path: path) })
    let boundary = try controllerEvent(#"{"type":"turn_end"}"#)
    let projectURL = try temporaryDirectory()

    await controller.openNew(projectURL: projectURL)
    let staleBoundary = controller.testingCapturedBoundaryReconciler(frame: boundary)

    await controller.restart()
    let currentBoundary = controller.testingCapturedBoundaryReconciler(frame: boundary)
    currentBoundary()
    staleBoundary()

    #expect(await loader.waitForRequestCount(3))
    #expect(await eventually {
        controller.visibleText(for: "current-history") == "current"
    })
    await manager.closeAll()
}

@MainActor @Test func restartStopsThePreviousProcessor() async throws {
    let manager = fakeManager(mode: "transcript-burst")
    let controller = SessionController(processManager: manager)

    await controller.openNew(projectURL: try temporaryDirectory())
    controller.draft = "burst"
    await controller.sendPrompt()
    #expect(await eventually {
        (controller.visibleText(for: "burst-message")?.count ?? 0) > 0
    })

    await controller.restart()
    try await Task.sleep(for: .milliseconds(300))

    #expect(controller.runtimeState == .idle)
    #expect(controller.visibleText(for: "burst-message") == nil)
    await manager.closeAll()
}

@MainActor @Test func extensionRequestsRemainLosslessDuringBurst() async throws {
    let manager = fakeManager(mode: "transcript-burst-extensions")
    let controller = SessionController(processManager: manager)

    await controller.openNew(projectURL: try temporaryDirectory())
    controller.draft = "burst"
    await controller.sendPrompt()

    #expect(await eventually {
        controller.visibleText(for: "burst-message")?.count == 1_000
            && controller.runtimeState == .idle
    })
    #expect(controller.extensionUIIDs == [
        "confirm-200",
        "confirm-400",
        "confirm-600",
        "confirm-800",
        "confirm-1000",
    ])
    await manager.closeAll()
}

@MainActor @Test func restartCancelsOldExtensionTimeouts() async throws {
    let manager = fakeManager(mode: "extension-timeout")
    let controller = SessionController(processManager: manager)

    await controller.openNew(projectURL: try temporaryDirectory())
    controller.draft = "timeout"
    await controller.sendPrompt()
    #expect(await eventually {
        controller.extensionUIIDs == ["timeout-confirm"]
    })

    await controller.restart()
    try await Task.sleep(for: .milliseconds(400))

    #expect(controller.runtimeState == .idle)
    #expect(controller.visibleText(for: "leaked-timeout-response") == nil)
    await manager.closeAll()
}

@MainActor @Test func delayedPromptSuccessAfterPipelineInvalidationCannotClearDraft() async throws {
    let manager = fakeManager(mode: "delayed-prompt-success")
    let controller = SessionController(processManager: manager)

    await controller.openNew(projectURL: try temporaryDirectory())
    controller.draft = "old prompt"
    let promptTask = Task { await controller.sendPrompt() }
    try await Task.sleep(for: .milliseconds(80))

    controller.draft = "replacement draft"
    controller.handleUnexpectedExit(code: 9, stderrTail: "boom")
    await promptTask.value

    #expect(controller.draft == "replacement draft")
    #expect(controller.runtimeState == .stopped(code: 9, stderrTail: "boom"))
    await manager.closeAll()
}

@MainActor @Test func delayedPromptFailureAfterRestartCannotFailReplacementSession() async throws {
    let manager = fakeManager(mode: "delayed-prompt-failure")
    let controller = SessionController(processManager: manager)

    await controller.openNew(projectURL: try temporaryDirectory())
    controller.draft = "old prompt"
    let promptTask = Task { await controller.sendPrompt() }
    try await Task.sleep(for: .milliseconds(80))

    await controller.restart()
    controller.draft = "replacement draft"
    await promptTask.value

    #expect(controller.draft == "replacement draft")
    #expect(controller.runtimeState == .idle)
    await manager.closeAll()
}

@MainActor @Test func staleOpeningHistoryLoadCannotReplaceNewerSession() async throws {
    let loader = OpeningRaceHistoryLoader()
    let manager = fakeManager(mode: "basic")
    let controller = SessionController(
        processManager: manager,
        historyLoader: { path in try await loader.load(path: path) })
    let projectURL = try temporaryDirectory()

    let firstOpen = Task { await controller.openNew(projectURL: projectURL) }
    #expect(await loader.waitForRequestCount(1))
    let secondOpen = Task { await controller.openNew(projectURL: projectURL) }
    await secondOpen.value
    await firstOpen.value

    #expect(controller.runtimeState == .idle)
    #expect(controller.visibleText(for: "stale-history") == nil)
    await manager.closeAll()
}

@MainActor @Test func closeDisposesHandleAndRejectsLaterBurstSnapshots() async throws {
    let manager = fakeManager(mode: "transcript-burst")
    let controller = SessionController(processManager: manager)

    await controller.openNew(projectURL: try temporaryDirectory())
    let sessionPath = try #require(controller.sessionPath)
    controller.draft = "burst"
    await controller.sendPrompt()
    #expect(await eventually {
        (controller.visibleText(for: "burst-message")?.count ?? 0) > 0
    })

    await controller.close()
    try await Task.sleep(for: .milliseconds(300))

    #expect(await manager.handle(for: sessionPath) == nil)
    #expect(controller.visibleText(for: "burst-message") == nil)
}

@MainActor @Test func disposeReturnsCloseTaskBeforeSamePathReuse() async throws {
    let manager = fakeManager(mode: "basic")
    let controller = SessionController(processManager: manager)
    let directory = try temporaryDirectory()
    let sessionPath = directory.appending(path: "reuse.jsonl").path

    await controller.openExisting(metadata(path: sessionPath, cwd: directory.path))
    #expect(await manager.handle(for: sessionPath) != nil)

    let closeTask = try #require(controller.dispose())
    await closeTask.value

    #expect(await manager.handle(for: sessionPath) == nil)
    let replacement = SessionController(processManager: manager)
    await replacement.openExisting(metadata(path: sessionPath, cwd: directory.path))
    #expect(await manager.handle(for: sessionPath) != nil)
    await manager.closeAll()
}

@MainActor @Test func inFlightSamePathReplacementDoesNotCloseReplacementHandle() async throws {
    let directory = try temporaryDirectory()
    let markerURL = directory.appending(path: "open-started")
    let manager = delayedFakeManager(mode: "basic", markerURL: markerURL)
    let sessionPath = directory.appending(path: "in-flight-reuse.jsonl").path
    let first = SessionController(processManager: manager)
    let replacement = SessionController(processManager: manager)
    let sessionMetadata = metadata(path: sessionPath, cwd: directory.path)

    let firstOpen = Task { await first.openExisting(sessionMetadata) }
    #expect(await eventually {
        FileManager.default.fileExists(atPath: markerURL.path)
    })

    let closeTask = first.dispose()
    let replacementOpen = Task {
        await closeTask?.value
        await replacement.openExisting(sessionMetadata)
    }
    await replacementOpen.value
    await firstOpen.value

    #expect(replacement.runtimeState == .idle)
    #expect(await manager.handle(for: sessionPath) != nil)
    await manager.closeAll()
}

@MainActor @Test func staleCapturedRemovalCannotRemoveSameIDExtensionInReplacementSession() async throws {
    let manager = fakeManager(mode: "extension-timeout")
    let controller = SessionController(processManager: manager)
    let projectURL = try temporaryDirectory()

    await controller.openNew(projectURL: projectURL)
    controller.draft = "first"
    await controller.sendPrompt()
    #expect(await eventually {
        controller.extensionUIIDs == ["timeout-confirm"]
    })
    let staleRemoval = controller.testingCapturedExtensionRemoval(id: "timeout-confirm")

    await controller.restart()
    controller.draft = "second"
    await controller.sendPrompt()
    #expect(await eventually {
        controller.extensionUIIDs == ["timeout-confirm"]
    })

    await staleRemoval()

    #expect(controller.extensionUIIDs == ["timeout-confirm"])
    await manager.closeAll()
}

@MainActor @Test func unexpectedExitRejectsLaterSnapshots() async throws {
    let manager = fakeManager(mode: "transcript-burst")
    let controller = SessionController(processManager: manager)
    controller.draft = "Keep this"

    await controller.openNew(projectURL: try temporaryDirectory())
    controller.draft = "burst"
    await controller.sendPrompt()
    #expect(await eventually {
        controller.visibleText(for: "burst-message") != nil
    })
    controller.handleUnexpectedExit(code: 9, stderrTail: "boom")
    let transcriptAtExit = controller.visibleText(for: "burst-message")

    try await Task.sleep(for: .milliseconds(200))
    #expect(controller.runtimeState == .stopped(code: 9, stderrTail: "boom"))
    #expect(controller.draft.isEmpty)
    #expect(controller.isRecoveryPresented)
    #expect(controller.visibleText(for: "burst-message") == transcriptAtExit)
    await manager.closeAll()
}

private func fakeManager(mode: String) -> SessionProcessManager {
    SessionProcessManager(clientFactory: { configuration in
        var fake = configuration
        fake.executable = "/usr/bin/env"
        fake.extraArguments = [
            "python3",
            repositoryRoot()
                .appending(path: "OmpKit/Tests/OmpKitTests/Fixtures/fake_server.py").path,
            mode,
        ]
        fake.rawArgv = true
        fake.cwd = nil
        return RpcClient(configuration: fake)
    })
}

private func delayedFakeManager(mode: String, markerURL: URL) -> SessionProcessManager {
    SessionProcessManager(clientFactory: { configuration in
        var fake = configuration
        fake.executable = "/bin/sh"
        fake.extraArguments = [
            "-c",
            #"touch "$0"; sleep 0.3; exec python3 "$1" "$2""#,
            markerURL.path,
            repositoryRoot()
                .appending(path: "OmpKit/Tests/OmpKitTests/Fixtures/fake_server.py").path,
            mode,
        ]
        fake.rawArgv = true
        fake.cwd = nil
        return RpcClient(configuration: fake)
    })
}

private func repositoryRoot() -> URL {
    URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "tenx-controller-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func metadata(
    path: String,
    cwd: String,
    title: String? = nil
) -> SessionMetadata {
    SessionMetadata(
        path: path,
        sessionId: URL(filePath: path).deletingPathExtension().lastPathComponent,
        cwd: cwd,
        title: title,
        created: Date(timeIntervalSince1970: 1_787_601_600),
        modified: Date(timeIntervalSince1970: 1_787_601_600),
        sizeBytes: 10,
        status: .complete)
}

private func writeHistoryMessage(_ text: String, to url: URL) throws {
    try Data("""
    {"type":"session","version":3,"id":"s","timestamp":"2026-08-24T20:00:00.000Z","cwd":"/tmp"}
    {"type":"message","id":"hist-message","parentId":null,"timestamp":"2026-08-24T20:00:01.000Z","message":{"role":"assistant","content":[{"type":"text","text":"\(text)"}],"timestamp":1787601601000}}
    """.utf8).write(to: url)
}

@MainActor
private func eventually(
    timeout: Duration = .seconds(5),
    _ predicate: @escaping @MainActor () -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout.seconds)
    while Date() < deadline {
        if predicate() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return predicate()
}

private func controllerEvent(_ json: String) throws -> RpcFrame {
    try RpcFrame.decode(line: Data(json.utf8))
}

private extension Duration {
    var seconds: TimeInterval {
        let components = components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

private extension SessionController {
    func visibleText(for id: String) -> String? {
        items.compactMap { item -> TranscriptMessage? in
            guard case .message(let message) = item, message.id == id else { return nil }
            return message
        }.first?.visibleText
    }

    var extensionUIIDs: [String] {
        items.compactMap { item in
            guard case .extensionUI(let state) = item else { return nil }
            return state.id
        }
    }
}

private actor DelayedHistoryLoader {
    private var requestCount = 0
    private var didCompleteDelayedFailure = false

    func load(path: String) async throws -> TranscriptHistory? {
        requestCount += 1
        switch requestCount {
        case 1:
            return nil
        case 2:
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                // Deliberately ignore cancellation to model a synchronous loader that
                // returns a stale failure after a newer boundary has already started.
            }
            didCompleteDelayedFailure = true
            throw ControlledHistoryError.failed
        default:
            return TranscriptHistory(items: [])
        }
    }

    func waitForRequestCount(
        _ count: Int,
        timeout: Duration = .seconds(5)
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout.seconds)
        while Date() < deadline {
            if requestCount >= count { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return requestCount >= count
    }

    func waitForDelayedFailureCompletion(timeout: Duration = .seconds(5)) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout.seconds)
        while Date() < deadline {
            if didCompleteDelayedFailure { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return didCompleteDelayedFailure
    }
}

private enum ControlledHistoryError: Error {
    case failed
}

private actor OpeningRaceHistoryLoader {
    private var requestCount = 0

    func load(path: String) async throws -> TranscriptHistory? {
        requestCount += 1
        if requestCount == 1 {
            try await Task.sleep(for: .milliseconds(300))
            return TranscriptHistory(items: [messageItem(id: "stale-history", text: "stale")])
        }
        return nil
    }

    func waitForRequestCount(
        _ count: Int,
        timeout: Duration = .seconds(5)
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout.seconds)
        while Date() < deadline {
            if requestCount >= count { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return requestCount >= count
    }
}

private actor CurrentReconciliationLoader {
    private var requestCount = 0

    func load(path: String) async throws -> TranscriptHistory? {
        requestCount += 1
        guard requestCount >= 3 else { return nil }
        try await Task.sleep(for: .milliseconds(200))
        return TranscriptHistory(items: [messageItem(id: "current-history", text: "current")])
    }

    func waitForRequestCount(
        _ count: Int,
        timeout: Duration = .seconds(5)
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout.seconds)
        while Date() < deadline {
            if requestCount >= count { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return requestCount >= count
    }
}

private func messageItem(id: String, text: String) -> TranscriptItem {
    .message(TranscriptMessage(
        id: id,
        raw: .object([
            "id": .string(id),
            "role": .string("assistant"),
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(text),
                ]),
            ]),
            "timestamp": .double(0),
        ]),
        isFinal: true))
}
