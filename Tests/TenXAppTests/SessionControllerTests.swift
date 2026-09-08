import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Suite @MainActor struct SessionControllerTests {

@MainActor @Test func contextPercentageIsClampedToItsDisplayRange() {
    #expect(SessionController.contextPercent(.object(["percentage": .double(210)])) == 100)
    #expect(SessionController.contextPercent(.object(["percentage": .double(-0.2)])) == 0)
    #expect(SessionController.contextPercent(.object(["percentage": .double(0.63)])) == 63)
}

@Test func ompContextPercentUsesPercentagePoints() {
    #expect(SessionController.contextPercent(.object(["percent": .double(1)])) == 1)
    #expect(SessionController.contextPercent(.object(["percent": .double(0.63)])) == 1)
}

@Test func contextDetailsDoNotSubmitOrAlterTheConversation() async throws {
    let manager = contextFakeManager(mode: "basic")
    let controller = SessionController(processManager: manager)
    await controller.openNew(projectURL: try temporaryDirectory())
    #expect(controller.contextUsage?.tokens == 85_000)
    controller.draft = "Keep this draft"
    let before = controller.items
    await controller.refreshContextDetails()
    #expect(controller.contextBreakdown?.usedTokens == 84_000)
    #expect(controller.contextBreakdown?.categories.count == 5)
    #expect(controller.contextErrorMessage == nil)
    #expect(controller.draft == "Keep this draft")
    #expect(controller.pendingSubmissions.isEmpty)
    #expect(controller.items == before)
    #expect(controller.runtimeState == .idle)
    #expect(!controller.isContextLoading)
    await manager.closeAll()
}

@Test func unavailableContextDetailsDoNotFailTheSession() async throws {
    for mode in ["malformed", "unsupported"] {
        let manager = contextFakeManager(mode: mode)
        let controller = SessionController(processManager: manager)
        await controller.openNew(projectURL: try temporaryDirectory())
        await controller.refreshContextDetails()
        #expect(controller.contextBreakdown == nil)
        #expect(controller.contextErrorMessage != nil)
        #expect(controller.contextUsage != nil)
        #expect(controller.runtimeState == .idle)
        await manager.closeAll()
    }
}

@Test func contextRefreshRecoversFromATransientReadFailure() async throws {
    let manager = contextFakeManager(mode: "transient")
    let controller = SessionController(processManager: manager)
    await controller.openNew(projectURL: try temporaryDirectory())
    let boundary = try #require(controller.testingCapturedControlConsumer(
        .event(type: "auto_compaction_end", payload: .object([:]))))
    await boundary()
    #expect(await eventually { controller.contextErrorMessage != nil })
    await boundary()
    #expect(await eventually { controller.contextUsage?.tokens == 87_000 })
    #expect(controller.contextErrorMessage == nil)
    await manager.closeAll()
}

@Test func contextRefreshesAfterCompactionBoundary() async throws {
    let manager = contextFakeManager(mode: "basic")
    let controller = SessionController(processManager: manager)
    await controller.openNew(projectURL: try temporaryDirectory())
    let boundary = try #require(controller.testingCapturedControlConsumer(
        .event(type: "auto_compaction_end", payload: .object([:]))))
    await boundary()
    #expect(await eventually { controller.contextUsage?.tokens == 86_000 })
    #expect(controller.runtimeState == .idle)
    await manager.closeAll()
}

@Test func ompSessionTitleGeneratorUsesTheActiveModelAndParsesTaggedOutput() async throws {
    let capture = TitleCommandCapture()
    let generator = OmpSessionTitleGenerator(
        executableURL: URL(filePath: "/opt/omp"),
        run: { executableURL, arguments in
            await capture.record(executableURL: executableURL, arguments: arguments)
            return Data("Working...\n<title>Fix untitled session naming</title>\n".utf8)
        })

    let title = await generator.generate(
        prompt: "The session still says Untitled session. Fix its name.",
        provider: "openai-codex",
        modelID: "gpt-5.6-sol")

    #expect(title == "Fix untitled session naming")
    let invocation = await capture.invocation
    #expect(invocation?.executableURL.path == "/opt/omp")
    #expect(invocation?.arguments.contains("openai-codex/gpt-5.6-sol") == true)
    #expect(invocation?.arguments.contains("--no-session") == true)
    #expect(invocation?.arguments.contains("--no-tools") == true)
    #expect(invocation?.arguments.last?.contains("<user>") == true)
}

@Test func ompSessionTitleGeneratorRejectsNonTitleOutput() {
    #expect(OmpSessionTitleGenerator.title(from: Data("<title/>".utf8)) == nil)
    #expect(OmpSessionTitleGenerator.title(from: Data("<title>none</title>".utf8)) == nil)
    #expect(OmpSessionTitleGenerator.title(from: Data("A helpful answer without title markers".utf8)) == nil)
    #expect(OmpSessionTitleGenerator.title(from: Data(
        "<title>one two three four five six seven eight nine ten eleven twelve thirteen</title>".utf8)) == nil)
}

@MainActor @Test func firstSuccessfulPromptPersistsGeneratedSessionTitleExactlyOnce() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let commandLogURL = directory.appending(path: "commands.log")
    let manager = commandLoggingFakeManager(commandLogURL: commandLogURL)
    let generator = OmpSessionTitleGenerator(
        executableURL: URL(filePath: "/opt/omp"),
        run: { _, _ in Data("<title>Fix untitled session naming</title>".utf8) })
    let controller = SessionController(
        processManager: manager,
        titleGenerator: generator)

    await controller.openNew(projectURL: directory)
    controller.draft = "The session still says Untitled session. Fix its name."
    await controller.sendPrompt()

    #expect(await eventually { controller.title == "Fix untitled session naming" })
    #expect(await eventually { controller.runtimeState == .idle })
    controller.draft = "A follow-up that must not rename it"
    await controller.sendPrompt()

    let commands = try String(contentsOf: commandLogURL, encoding: .utf8)
        .split(separator: "\n")
        .map(String.init)
    #expect(commands.filter { $0 == "set_session_name" }.count == 1)
    let promptIndex = try #require(commands.firstIndex(of: "prompt"))
    let titleIndex = try #require(commands.firstIndex(of: "set_session_name"))
    #expect(promptIndex < titleIndex)
    await manager.closeAll()
}

@MainActor @Test func acknowledgedInitialPromptPersistsBoundedFallbackWithoutAGenerator() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let sessionFile = directory.appending(path: "bucket/fallback.jsonl")
    try writeTitleSession(at: sessionFile, projectURL: directory)
    let commandLogURL = directory.appending(path: "commands.jsonl")
    let manager = titleFakeManager(sessionFile: sessionFile, commandLogURL: commandLogURL)
    let controller = SessionController(processManager: manager)
    let prompt = "   \(String(repeating: "A", count: 100))   \nignored"
    let expected = String(repeating: "A", count: 80)

    controller.prepareInitialSubmission(text: prompt, attachments: [], projectURL: directory)
    await controller.openNew(projectURL: directory)
    await controller.sendPrompt()

    #expect(await eventually { controller.title == expected })
    let entries = try titleCommandEntries(at: commandLogURL)
    #expect(entries.filter { $0["type"] == "set_session_name" }.count == 1)
    #expect(entries.first { $0["type"] == "set_session_name" }?["title"] == expected)
    let reopened = await SessionLibrary(root: directory).listAll()
    #expect(reopened.first?.title == expected)
    await manager.closeAll()
}

@MainActor @Test func unusableGeneratedTitleFallsBackToTheInitialPrompt() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let sessionFile = directory.appending(path: "bucket/fallback.jsonl")
    try writeTitleSession(at: sessionFile, projectURL: directory)
    let commandLogURL = directory.appending(path: "commands.jsonl")
    let manager = titleFakeManager(sessionFile: sessionFile, commandLogURL: commandLogURL)
    let generator = OmpSessionTitleGenerator(
        executableURL: URL(filePath: "/opt/omp"),
        run: { _, _ in Data("<title/>".utf8) })
    let controller = SessionController(processManager: manager, titleGenerator: generator)

    controller.prepareInitialSubmission(
        text: "  Useful fallback title  ", attachments: [], projectURL: directory)
    await controller.openNew(projectURL: directory)
    await controller.sendPrompt()

    #expect(await eventually { controller.title == "Useful fallback title" })
    let entries = try titleCommandEntries(at: commandLogURL)
    #expect(entries.filter { $0["type"] == "set_session_name" }.count == 1)
    #expect(entries.first { $0["type"] == "set_session_name" }?["title"]
        == "Useful fallback title")
    await manager.closeAll()
}

@MainActor @Test func rejectedInitialPromptDoesNotPersistAFallbackTitle() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let sessionFile = directory.appending(path: "bucket/rejected.jsonl")
    try writeTitleSession(at: sessionFile, projectURL: directory)
    let commandLogURL = directory.appending(path: "commands.jsonl")
    let manager = titleFakeManager(
        sessionFile: sessionFile, commandLogURL: commandLogURL, rejectPrompt: true)
    let controller = SessionController(processManager: manager)

    controller.prepareInitialSubmission(text: "Do not name me", attachments: [], projectURL: directory)
    await controller.openNew(projectURL: directory)
    await controller.sendPrompt()

    let entries = try titleCommandEntries(at: commandLogURL)
    #expect(entries.allSatisfy { $0["type"] != "set_session_name" })
    await manager.closeAll()
}

@MainActor @Test func manualRenameWinsOverADelayedGeneratedTitle() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let sessionFile = directory.appending(path: "bucket/manual.jsonl")
    try writeTitleSession(at: sessionFile, projectURL: directory)
    let commandLogURL = directory.appending(path: "commands.jsonl")
    let manager = titleFakeManager(sessionFile: sessionFile, commandLogURL: commandLogURL)
    let gate = LoadGate()
    let generator = OmpSessionTitleGenerator(
        executableURL: URL(filePath: "/opt/omp"),
        run: { _, _ in
            await gate.started()
            await gate.waitForRelease()
            return Data("<title>Generated too late</title>".utf8)
        })
    let controller = SessionController(processManager: manager, titleGenerator: generator)
    controller.prepareInitialSubmission(text: "Fallback", attachments: [], projectURL: directory)
    await controller.openNew(projectURL: directory)
    await controller.sendPrompt()
    await gate.waitForStart()

    let rename = Task { try await controller.rename(to: "Manual title") }
    await gate.release()
    try await rename.value

    #expect(controller.title == "Manual title")
    let entries = try titleCommandEntries(at: commandLogURL)
    #expect(entries.filter { $0["type"] == "set_session_name" }.count == 1)
    #expect(entries.first { $0["type"] == "set_session_name" }?["title"] == "Manual title")
    await manager.closeAll()
}

@MainActor @Test func sessionReplacementCancelsADelayedGeneratedTitle() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let sessionFile = directory.appending(path: "bucket/first.jsonl")
    try writeTitleSession(at: sessionFile, projectURL: directory)
    let commandLogURL = directory.appending(path: "commands.jsonl")
    let manager = titleFakeManager(sessionFile: sessionFile, commandLogURL: commandLogURL)
    let gate = LoadGate()
    let generator = OmpSessionTitleGenerator(
        executableURL: URL(filePath: "/opt/omp"),
        run: { _, _ in
            await gate.started()
            await gate.waitForRelease()
            return Data("<title>Generated too late</title>".utf8)
        })
    let controller = SessionController(processManager: manager, titleGenerator: generator)
    controller.prepareInitialSubmission(text: "Fallback", attachments: [], projectURL: directory)
    await controller.openNew(projectURL: directory)
    await controller.sendPrompt()
    await gate.waitForStart()

    await controller.openExisting(metadata(
        path: directory.appending(path: "second.jsonl").path,
        cwd: directory.path,
        title: "Second session"))
    await gate.release()
    for _ in 0..<20 { await Task.yield() }

    #expect(controller.title == "Second session")
    let entries = try titleCommandEntries(at: commandLogURL)
    #expect(entries.allSatisfy { $0["type"] != "set_session_name" })
    await manager.closeAll()
}

@MainActor @Test func terminalAgentBoundaryRefreshesRealGitMetadataButNonterminalDoesNot() async throws {
    let repository = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: repository) }
    try runTitleGit(["init", "-b", "branch-a"], at: repository)
    let manager = fakeManager(mode: "basic")
    let controller = SessionController(processManager: manager)
    await controller.openNew(projectURL: repository)
    #expect(controller.headerMetadata.branch == "branch-a")

    try runTitleGit(["switch", "-c", "branch-b"], at: repository)
    let terminal = try #require(controller.testingCapturedControlConsumer(
        .event(type: "agent_end", payload: .object(["isTerminal": .bool(true)]))))
    await terminal()
    await controller.testingAwaitHeaderMetadataRefresh()
    #expect(controller.headerMetadata.branch == "branch-b")

    try runTitleGit(["switch", "-c", "branch-c"], at: repository)
    let nonterminal = try #require(controller.testingCapturedControlConsumer(
        .event(type: "agent_end", payload: .object(["isTerminal": .bool(false)]))))
    await nonterminal()
    for _ in 0..<20 { await Task.yield() }
    #expect(controller.headerMetadata.branch == "branch-b")
    await manager.closeAll()
}

@MainActor @Test func overlappingMetadataRefreshesCoalesceAndStaleProjectResultIsIgnored() async throws {
    let firstProject = try temporaryDirectory()
    let secondProject = try temporaryDirectory()
    defer {
        try? FileManager.default.removeItem(at: firstProject)
        try? FileManager.default.removeItem(at: secondProject)
    }
    let resolver = ControlledHeaderMetadataResolver()
    let manager = fakeManager(mode: "basic")
    let controller = SessionController(
        processManager: manager,
        headerMetadataResolver: { url in await resolver.resolve(url) })
    await controller.openNew(projectURL: firstProject)
    let boundary = try controllerEvent(#"{"type":"agent_end","isTerminal":true}"#)
    let first = try #require(controller.testingCapturedControlConsumer(boundary))
    let second = try #require(controller.testingCapturedControlConsumer(boundary))

    await first()
    await second()
    await resolver.waitForDelayedRequest()
    #expect(await resolver.requestCount == 2)

    await controller.openExisting(metadata(
        path: secondProject.appending(path: "second.jsonl").path,
        cwd: secondProject.path,
        title: "Second"))
    await resolver.releaseDelayedRequest()
    for _ in 0..<20 { await Task.yield() }

    #expect(controller.headerMetadata.branch == "second-current")
    #expect(await resolver.requestCount == 3)
    await manager.closeAll()
}

@MainActor @Test func providerIDReadsOnlyANonemptyProviderFromAModelObject() {
    #expect(SessionController.providerID(from: .object([
        "id": .string("claude-sonnet"),
        "provider": .string("anthropic"),
    ])) == "anthropic")
    #expect(SessionController.providerID(from: .string("claude-sonnet")) == nil)
    #expect(SessionController.providerID(from: nil) == nil)
}

@MainActor @Test func activeProviderAccountStateKeepsOnlyOpaqueStringReferences() {
    #expect(SessionController.activeProviderAccountRefs(from: .object([
        "activeProviderAccounts": .object([
            "openai-codex": .string("acct_A"),
            "anthropic": .string("acct_B"),
            "invalid": .int(3),
        ]),
    ])) == [
        "openai-codex": "acct_A",
        "anthropic": "acct_B",
    ])
    #expect(SessionController.activeProviderAccountRefs(from: nil).isEmpty)
}

@MainActor @Test func controllerForwardsOnlyMonotonicallyNewerAccountChangesToTheCoordinator() {
    let coordinator = ProviderAccountCoordinator()
    let controller = SessionController(
        processManager: SessionProcessManager(),
        previewItems: [],
        runtimeState: .streaming,
        providerID: "openai-codex",
        activityRegistry: coordinator)

    controller.handleProviderAccountChange(ProviderAccountChangedEvent(
        providerID: "openai-codex",
        accountRef: "acct_B",
        reason: .automaticFailover,
        sequence: 2))
    controller.handleProviderAccountChange(ProviderAccountChangedEvent(
        providerID: "openai-codex",
        accountRef: "acct_A",
        reason: .manual,
        sequence: 1))

    let key = ProviderAccountKey(providerID: "openai-codex", accountRef: "acct_B")
    #expect(controller.currentProviderAccountRef == "acct_B")
    #expect(controller.providerAccountSequence == 2)
    #expect(coordinator.activeAccountRefs[controller.id] == "acct_B")
    #expect(coordinator.generatingCounts == [key: 1])
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

@MainActor @Test func markerFramesReachTheAccountChannelWhileOrdinaryInputReachesTheTranscript() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = try makeProviderAccountChannelExecutable(in: directory)
    let manager = SessionProcessManager(executable: executable.path)
    let registry = ProviderAccountChannelRegistry()
    let controller = SessionController(
        processManager: manager,
        accountChannelRegistry: registry)

    await controller.openExisting(metadata(path: "/tmp/account-channel-session.jsonl", cwd: "/tmp"))

    #expect(await eventually { registry.entry(for: controller.id) != nil })
    let channel = try #require(registry.entry(for: controller.id)?.channel)

    let reply = try await channel.send(ProviderAccountChannelCommand(
        id: "cmd-1", command: "pin_account", params: [:]))

    #expect(reply == .object(["applied": .bool(true)]))
    #expect(await eventually { controller.extensionUIIDs.contains("sheet-1") })
    #expect(controller.hasPendingUserInput)
    #expect(controller.runtimeState == .idle)
    await manager.closeAll()
}

@MainActor @Test func sameProcessStateRefreshPreservesAccountEventSequence() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = try makeProviderAccountRefreshExecutable(in: directory)
    let manager = SessionProcessManager(executable: executable.path)
    let controller = SessionController(processManager: manager)

    await controller.openExisting(metadata(path: "/tmp/account-refresh.jsonl", cwd: "/tmp"))

    #expect(await eventually { controller.title == "Refresh complete" })
    #expect(controller.currentProviderAccountRef == "acct_C")
    #expect(controller.providerAccountSequence == 3)
    await manager.closeAll()
}

}

@MainActor
private func controllerStateReaches(_ predicate: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: .seconds(30))
    while ContinuousClock.now < deadline {
        if predicate() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return predicate()
}

@MainActor extension SessionControllerTests {

@MainActor @Test func managedPromptAdmissionRejectsANewTurnDuringAccountRemoval() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = try makeProviderAccountExecutable(in: directory)
    let manager = SessionProcessManager(executable: executable.path)
    let coordinator = ProviderAccountCoordinator()
    let controller = SessionController(processManager: manager, activityRegistry: coordinator)
    await controller.openExisting(metadata(path: "/tmp/account-session.jsonl", cwd: "/tmp"))
    #expect(await eventually {
        controller.currentProviderAccountRef == "acct_B" && controller.runtimeState == .idle
    })
    let target = providerAccountFixture(
        providerID: "openai-codex",
        ref: "acct_A",
        label: "Personal",
        order: 0)
    let remaining = providerAccountFixture(
        providerID: "openai-codex",
        ref: "acct_B",
        label: "Work",
        order: 1)
    let rpcGate = LoadGate()
    let removal = Task {
        try await coordinator.removeAccount(
            providerID: "openai-codex",
            accountRef: "acct_A",
            accounts: [target, remaining]
        ) {
            await rpcGate.started()
            await rpcGate.waitForRelease()
            return ProviderAccountRemovalResult(removed: true, accounts: [remaining])
        }
    }
    await rpcGate.waitForStart()

    controller.draft = "Keep this draft"
    await controller.sendPrompt()

    #expect(controller.draft == "Keep this draft")
    #expect(controller.runtimeState == .idle)

    await rpcGate.release()
    _ = try await removal.value
    await manager.closeAll()
}

@MainActor @Test func accountEventCapturedFromClosedPipelineIsIgnored() async throws {
    let manager = fakeManager(mode: "basic")
    let controller = SessionController(processManager: manager)
    await controller.openExisting(metadata(path: "/tmp/stale-account-event.jsonl", cwd: "/tmp"))
    let consumeStaleEvent = try #require(controller.testingCapturedControlConsumer(
        .providerAccountChanged(ProviderAccountChangedEvent(
            providerID: "openai-codex",
            accountRef: "acct_stale",
            reason: .automaticFailover,
            sequence: 10))))

    await controller.close()
    await consumeStaleEvent()

    #expect(controller.currentProviderAccountRef == nil)
    #expect(controller.providerAccountSequence == 0)
    await manager.closeAll()
}

@MainActor @Test func accountControlFromActivePipelineUpdatesController() async throws {
    let manager = fakeManager(mode: "basic")
    let controller = SessionController(processManager: manager)
    await controller.openExisting(metadata(path: "/tmp/active-account-event.jsonl", cwd: "/tmp"))
    let applyAccountChange = try #require(controller.testingCapturedControlConsumer(
        .providerAccountChanged(ProviderAccountChangedEvent(
            providerID: "test",
            accountRef: "acct_active",
            reason: .manual,
            sequence: 4))))

    await applyAccountChange()

    #expect(controller.currentProviderAccountRef == "acct_active")
    #expect(controller.providerAccountSequence == 4)
    await manager.closeAll()
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

@MainActor @Test func defaultControllerHistoryLoaderReusesUnchangedMappedHistory() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let sessionURL = directory.appending(path: "history.jsonl")
    try writeHistoryTool(to: sessionURL)
    let manager = fakeManager(mode: "no-session-file")
    let controller = SessionController(processManager: manager)

    await controller.openExisting(metadata(path: sessionURL.path, cwd: directory.path))
    let initialContentID = try #require(controller.toolSourceContentID(for: "tool-1"))
    let boundary = try controllerEvent(#"{"type":"turn_end"}"#)
    let reconcile = controller.testingCapturedBoundaryReconciler(frame: boundary)
    reconcile()
    await controller.testingAwaitReconciliation()

    #expect(controller.toolSourceContentID(for: "tool-1") == initialContentID)
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

@MainActor @Test func adjacentReconciliationBoundariesPerformOneHistoryLoad() async throws {
    let loader = CountingHistoryLoader()
    let manager = fakeManager(mode: "basic")
    let controller = SessionController(
        processManager: manager,
        historyLoader: { path in try await loader.load(path: path) })
    let boundary = try controllerEvent(#"{"type":"turn_end"}"#)

    await controller.openNew(projectURL: try temporaryDirectory())
    let loadsAfterOpen = await loader.requestCount
    let first = controller.testingCapturedBoundaryReconciler(frame: boundary)
    let second = controller.testingCapturedBoundaryReconciler(frame: boundary)
    // Both boundaries land inside one debounce window; the second cancels the
    // first's pending load before it can start.
    first()
    second()
    await controller.testingAwaitReconciliation()

    #expect(await loader.requestCount == loadsAfterOpen + 1)
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

@MainActor @Test func failedNewSessionAfterExistingClearsPathAndPreservesPromptForReview() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = fakeManager { configuration in
        configuration.resumeSessionPath == nil ? "crash-after-negotiation" : "basic"
    }
    let controller = SessionController(processManager: manager)
    let existingPath = directory.appending(path: "existing.jsonl").path

    await controller.openExisting(metadata(path: existingPath, cwd: directory.path))
    #expect(controller.sessionPath != nil)
    controller.prepareInitialSubmission(
        text: "Preserve this new prompt",
        attachments: [],
        projectURL: directory)

    await controller.openNew(projectURL: directory)
    controller.markInitialSubmissionFailed()

    #expect(controller.sessionPath == nil)
    #expect(controller.draft == "Preserve this new prompt")
    guard case .failed = controller.runtimeState else {
        Issue.record("Expected the new session to report its opening failure")
        return
    }
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

private struct StubHarnessSummarizer: HarnessNoticeSummarizing {
    let summary: String?
    func summarize(_ descriptor: HarnessMessageDescriptor) async -> String? {
        summary
    }
}

@MainActor @Test func droppedHarnessMessagesBecomeNoticesThatUpdateInPlace() async throws {
    let container = URL(filePath: NSTemporaryDirectory())
        .appendingPathComponent("controller-notices-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: container) }
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    let executable = try makeNavigationExecutable(in: container, mode: "activity-lifecycle")
    let processManager = SessionProcessManager(executable: executable.path)

    let suiteName = "harness-notice-controller-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let preferences = HarnessNoticePreferenceStore(defaults: defaults)
    preferences.isEnabled = true

    let descriptor = HarnessMessageDescriptor(
        role: "developer",
        customType: nil,
        byteCount: 13,
        text: "Plan approved.")
    let controller = SessionController(
        processManager: processManager,
        historyLoader: { _ in TranscriptHistory(items: [], dropped: [descriptor]) },
        harnessNoticePreferences: preferences,
        harnessNoticeSummarizer: StubHarnessSummarizer(summary: "A plan-approval gate."))
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

    var noticeMessage: String?
    for _ in 0..<100 {
        noticeMessage = controller.items.compactMap { item -> String? in
            guard case .notice(_, _, let message) = item else { return nil }
            return message
        }.first
        if noticeMessage?.contains("A plan-approval gate.") == true { break }
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(noticeMessage == "Hidden developer message (13 chars): A plan-approval gate.")

    await processManager.closeAll()
}

@MainActor @Test func droppedHarnessMessagesStaySilentWhenThePreferenceIsOff() async throws {
    let container = URL(filePath: NSTemporaryDirectory())
        .appendingPathComponent("controller-notices-off-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: container) }
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    let executable = try makeNavigationExecutable(in: container, mode: "activity-lifecycle")
    let processManager = SessionProcessManager(executable: executable.path)

    let suiteName = "harness-notice-off-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let preferences = HarnessNoticePreferenceStore(defaults: defaults)

    let descriptor = HarnessMessageDescriptor(
        role: "developer",
        customType: nil,
        byteCount: 13,
        text: "Plan approved.")
    let controller = SessionController(
        processManager: processManager,
        historyLoader: { _ in TranscriptHistory(items: [], dropped: [descriptor]) },
        harnessNoticePreferences: preferences,
        harnessNoticeSummarizer: StubHarnessSummarizer(summary: "unused"))
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
    try await Task.sleep(for: .milliseconds(200))

    #expect(controller.items.allSatisfy {
        if case .notice = $0 { return false }
        return true
    })

    await processManager.closeAll()
}

@MainActor @Test func aFailedSummaryLeavesTheStaticNoticeText() async throws {
    let container = URL(filePath: NSTemporaryDirectory())
        .appendingPathComponent("controller-notices-nil-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: container) }
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    let executable = try makeNavigationExecutable(in: container, mode: "activity-lifecycle")
    let processManager = SessionProcessManager(executable: executable.path)

    let suiteName = "harness-notice-nil-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let preferences = HarnessNoticePreferenceStore(defaults: defaults)
    preferences.isEnabled = true

    let descriptor = HarnessMessageDescriptor(
        role: "developer",
        customType: nil,
        byteCount: 13,
        text: "Plan approved.")
    let controller = SessionController(
        processManager: processManager,
        historyLoader: { _ in TranscriptHistory(items: [], dropped: [descriptor]) },
        harnessNoticePreferences: preferences,
        harnessNoticeSummarizer: StubHarnessSummarizer(summary: nil))
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

    var noticeMessage: String?
    for _ in 0..<100 {
        noticeMessage = controller.items.compactMap { item -> String? in
            guard case .notice(_, _, let message) = item else { return nil }
            return message
        }.first
        if noticeMessage != nil { break }
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(noticeMessage == "Hidden developer message (13 chars)")

    await processManager.closeAll()
}

@MainActor @Test func droppedHarnessMessagesBelowTheThresholdStaySilent() async throws {
    let container = URL(filePath: NSTemporaryDirectory())
        .appendingPathComponent("controller-notices-threshold-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: container) }
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    let executable = try makeNavigationExecutable(in: container, mode: "activity-lifecycle")
    let processManager = SessionProcessManager(executable: executable.path)

    let suiteName = "harness-notice-threshold-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let preferences = HarnessNoticePreferenceStore(defaults: defaults)
    preferences.isEnabled = true
    preferences.threshold = 1_000

    let descriptor = HarnessMessageDescriptor(
        role: "developer",
        customType: nil,
        byteCount: 13,
        text: "Plan approved.")
    let controller = SessionController(
        processManager: processManager,
        historyLoader: { _ in TranscriptHistory(items: [], dropped: [descriptor]) },
        harnessNoticePreferences: preferences,
        harnessNoticeSummarizer: StubHarnessSummarizer(summary: "unused"))
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
    try await Task.sleep(for: .milliseconds(200))

    #expect(controller.items.allSatisfy {
        if case .notice = $0 { return false }
        return true
    })

    await processManager.closeAll()
}

}

private func contextFakeManager(mode: String) -> SessionProcessManager {
    SessionProcessManager(clientFactory: { configuration in
        var fake = configuration
        fake.executable = "/usr/bin/env"
        fake.extraArguments = ["python3", repositoryRoot().appending(path:
            "Tests/TenXAppTests/Fixtures/context_fake_server.py").path, mode]
        fake.rawArgv = true
        fake.cwd = nil
        return RpcClient(configuration: fake)
    })
}

private func fakeManager(mode: String) -> SessionProcessManager {
    fakeManager { _ in mode }
}

private func fakeManager(
    mode: @escaping @Sendable (RpcClientConfiguration) -> String
) -> SessionProcessManager {
    SessionProcessManager(clientFactory: { configuration in
        var fake = configuration
        fake.executable = "/usr/bin/env"
        fake.extraArguments = [
            "python3",
            repositoryRoot()
                .appending(path: "OmpKit/Tests/OmpKitTests/Fixtures/fake_server.py").path,
            mode(configuration),
        ]
        fake.rawArgv = true
        fake.cwd = nil
        return RpcClient(configuration: fake)
    })
}

private func commandLoggingFakeManager(commandLogURL: URL) -> SessionProcessManager {
    SessionProcessManager(clientFactory: { configuration in
        var fake = configuration
        fake.executable = "/usr/bin/env"
        fake.extraArguments = [
            "python3",
            repositoryRoot()
                .appending(path: "OmpKit/Tests/OmpKitTests/Fixtures/fake_server.py").path,
            "command-log",
            commandLogURL.path,
        ]
        fake.rawArgv = true
        fake.cwd = nil
        return RpcClient(configuration: fake)
    })
}

private func titleFakeManager(
    sessionFile: URL,
    commandLogURL: URL,
    rejectPrompt: Bool = false
) -> SessionProcessManager {
    SessionProcessManager(clientFactory: { configuration in
        var fake = configuration
        fake.executable = "/usr/bin/env"
        fake.extraArguments = [
            "python3",
            repositoryRoot().appending(path:
                "Tests/TenXAppTests/Fixtures/title_fake_server.py").path,
            sessionFile.path,
            commandLogURL.path,
        ] + (rejectPrompt ? ["reject"] : [])
        fake.rawArgv = true
        fake.cwd = nil
        return RpcClient(configuration: fake)
    })
}

private func writeTitleSession(at url: URL, projectURL: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let header = """
    {"type":"session","version":3,"id":"title-test","timestamp":"2026-09-08T00:00:00.000Z","cwd":"\(projectURL.path)"}
    """
    try Data((header + "\n").utf8).write(to: url)
}

private func titleCommandEntries(at url: URL) throws -> [[String: String]] {
    try String(contentsOf: url, encoding: .utf8)
        .split(whereSeparator: \.isNewline)
        .map { try JSONDecoder().decode([String: String].self, from: Data($0.utf8)) }
}

private actor TitleCommandCapture {
    private(set) var invocation: (executableURL: URL, arguments: [String])?

    func record(executableURL: URL, arguments: [String]) {
        invocation = (executableURL, arguments)
    }
}

private actor ControlledHeaderMetadataResolver {
    private let gate = LoadGate()
    private(set) var requestCount = 0

    func resolve(_ url: URL) async -> SessionHeaderMetadata {
        requestCount += 1
        switch requestCount {
        case 1:
            return SessionHeaderMetadata(branch: "first-initial", repo: url.lastPathComponent,
                worktreePath: nil)
        case 2:
            await gate.started()
            await gate.waitForRelease()
            return SessionHeaderMetadata(branch: "first-stale", repo: url.lastPathComponent,
                worktreePath: nil)
        default:
            return SessionHeaderMetadata(branch: "second-current", repo: url.lastPathComponent,
                worktreePath: nil)
        }
    }

    func waitForDelayedRequest() async {
        await gate.waitForStart()
    }

    func releaseDelayedRequest() async {
        await gate.release()
    }
}

private func runTitleGit(_ arguments: [String], at repository: URL) throws {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/git")
    process.arguments = ["-C", repository.path] + arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw CocoaError(.fileWriteUnknown)
    }
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
    TemporaryDirectoryRegistry.shared.register(url)
    return url
}

/// Removes the directories `temporaryDirectory()` hands out when the test host
/// exits.
///
/// The process owns this rather than each test, because most callers pass the
/// directory straight into `openNew(projectURL:)` with no local to hang a
/// `defer` on, and Swift Testing has no teardown hook for free `@Test`
/// functions. Left unmanaged these never got deleted: thousands of
/// `tenx-controller-*` directories pile up in the temp folder, and once that
/// folder is large enough `mktemp` starts failing — which surfaces as
/// resource-shaped failures in unrelated suites much later in a run.
private final class TemporaryDirectoryRegistry: @unchecked Sendable {
    static let shared = TemporaryDirectoryRegistry()

    private let lock = NSLock()
    private var urls: [URL] = []

    private init() {
        atexit { TemporaryDirectoryRegistry.shared.removeAll() }
    }

    func register(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        urls.append(url)
    }

    private func removeAll() {
        lock.lock()
        let pending = urls
        urls.removeAll()
        lock.unlock()
        for url in pending { try? FileManager.default.removeItem(at: url) }
    }
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

private func writeHistoryTool(to url: URL) throws {
    try Data("""
    {"type":"session","version":3,"id":"s","timestamp":"2026-08-24T20:00:00.000Z","cwd":"/tmp"}
    {"type":"message","id":"assistant","parentId":null,"timestamp":"2026-08-24T20:00:01.000Z","message":{"role":"assistant","content":[{"type":"toolCall","id":"tool-1","name":"read","arguments":{"path":"App.swift"}}],"timestamp":1787601601000}}
    {"type":"message","id":"result","parentId":"assistant","timestamp":"2026-08-24T20:00:02.000Z","message":{"role":"toolResult","toolCallId":"tool-1","toolName":"read","content":[{"type":"text","text":"let value = 1"}],"timestamp":1787601602000,"isError":false}}
    """.utf8).write(to: url)
}

private extension SessionController {
    func toolSourceContentID(for id: String) -> UUID? {
        items.compactMap { item -> ToolPresentation? in
            guard case .tool(let tool) = item, tool.id == id else { return nil }
            return tool
        }.first.flatMap { tool in
            guard case .source(let source, _) = tool.content.body else { return nil }
            return source.contentID
        }
    }
}

/// Emits the marker `extension_ui_request` (`tenx.provider-accounts.v1`)
/// alongside an ordinary, non-marker `input` request right after
/// `set_subagent_subscription`, mirroring where `makeProviderAccountExecutable`
/// above bundles its own extra frames. On receiving the client's
/// `extension_ui_response` for the marker request, decodes the wire-encoded
/// command from its `value` field and echoes a reply as the `placeholder`
/// of the *next* marker request — exactly the wire contract
/// `ProviderAccountExtensionChannel` implements (reply arrives on the next
/// request, never as the response's own payload).
private func makeProviderAccountChannelExecutable(in directory: URL) throws -> URL {
    let executable = directory.appending(path: "provider-account-channel-server.py")
    let source = #"""
    #!/usr/bin/env python3
    import json
    import sys

    def emit(value):
        print(json.dumps(value, separators=(",", ":")), flush=True)

    MARKER = "tenx.provider-accounts.v1"

    emit({"type":"ready","protocolVersion":1,"supportedProtocolVersions":[1,2],"maxFrameBytes":1048576,"maxReassembledFrameBytes":67108864})
    for line in sys.stdin:
        command = json.loads(line)
        request_id = command.get("id")
        command_type = command.get("type")
        if command_type == "negotiate_protocol":
            data = {"protocolVersion":2}
        elif command_type == "get_state":
            data = {"model":{"id":"gpt-test","provider":"openai-codex"},"isStreaming":False,"sessionFile":"/tmp/account-channel-session.jsonl"}
        elif command_type == "get_messages_page":
            data = {"messages":[],"nextCursor":None}
        elif command_type == "set_subagent_subscription":
            emit({"id":request_id,"type":"response","command":command_type,"success":True,"data":{}})
            emit({"type":"extension_ui_request","id":"acct-chan-1","method":"input","title":MARKER})
            emit({"type":"extension_ui_request","id":"sheet-1","method":"input","title":"Pick a color"})
            continue
        elif command_type == "extension_ui_response" and request_id == "acct-chan-1":
            sent = json.loads(command.get("value", "{}"))
            reply = json.dumps({"id": sent.get("id"), "ok": True, "data": {"applied": True}})
            emit({"type":"extension_ui_request","id":"acct-chan-2","method":"input","title":MARKER,"placeholder":reply})
            continue
        else:
            data = {}
        emit({"id":request_id,"type":"response","command":command_type,"success":True,"data":data})
    """#
    try Data(source.utf8).write(to: executable)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: executable.path)
    return executable
}

private func makeProviderAccountExecutable(in directory: URL) throws -> URL {
    let executable = directory.appending(path: "provider-account-server.py")
    let source = #"""
    #!/usr/bin/env python3
    import json
    import sys

    def emit(value):
        print(json.dumps(value, separators=(",", ":")), flush=True)

    emit({"type":"ready","protocolVersion":1,"supportedProtocolVersions":[1,2],"maxFrameBytes":1048576,"maxReassembledFrameBytes":67108864})
    for line in sys.stdin:
        command = json.loads(line)
        request_id = command.get("id")
        command_type = command.get("type")
        if command_type == "negotiate_protocol":
            data = {"protocolVersion":2}
        elif command_type == "get_state":
            data = {"model":{"id":"gpt-test","provider":"openai-codex"},"isStreaming":True,"sessionFile":"/tmp/account-session.jsonl","activeProviderAccounts":{"openai-codex":"acct_A"}}
        elif command_type == "get_messages_page":
            data = {"messages":[],"nextCursor":None}
        elif command_type == "set_subagent_subscription":
            data = {}
            emit({"id":request_id,"type":"response","command":command_type,"success":True,"data":data})
            emit({"type":"provider_account_changed","providerId":"openai-codex","accountRef":"acct_B","reason":"automaticFailover","sequence":2})
            emit({"type":"agent_end","messages":[],"isTerminal":True})
            continue
        else:
            data = {}
        emit({"id":request_id,"type":"response","command":command_type,"success":True,"data":data})
    """#
    try Data(source.utf8).write(to: executable)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: executable.path)
    return executable
}

private func makeProviderAccountRefreshExecutable(in directory: URL) throws -> URL {
    let executable = directory.appending(path: "provider-account-refresh-server.py")
    let source = #"""
    #!/usr/bin/env python3
    import json
    import sys
    import time

    def emit(value):
        print(json.dumps(value, separators=(",", ":")), flush=True)

    state_requests = 0
    emit({"type":"ready","protocolVersion":1,"supportedProtocolVersions":[1,2],"maxFrameBytes":1048576,"maxReassembledFrameBytes":67108864})
    for line in sys.stdin:
        command = json.loads(line)
        request_id = command.get("id")
        command_type = command.get("type")
        if command_type == "negotiate_protocol":
            data = {"protocolVersion":2}
        elif command_type == "get_state":
            state_requests += 1
            account_ref = "acct_A" if state_requests == 1 else "acct_C"
            data = {"sessionName":"Refresh","model":{"id":"gpt-test","provider":"openai-codex"},"isStreaming":False,"sessionFile":"/tmp/account-refresh.jsonl","activeProviderAccounts":{"openai-codex":account_ref}}
        elif command_type == "get_messages_page":
            data = {"messages":[],"nextCursor":None}
        elif command_type == "set_subagent_subscription":
            emit({"id":request_id,"type":"response","command":command_type,"success":True,"data":{}})
            emit({"type":"provider_account_changed","providerId":"openai-codex","accountRef":"acct_C","reason":"automaticFailover","sequence":3})
            emit({"type":"model_changed","model":{"id":"gpt-test","provider":"openai-codex"}})
            continue
        else:
            data = {}
        emit({"id":request_id,"type":"response","command":command_type,"success":True,"data":data})
        if command_type == "get_state" and state_requests == 2:
            time.sleep(0.05)
            emit({"type":"provider_account_changed","providerId":"openai-codex","accountRef":"acct_B","reason":"automaticFailover","sequence":2})
            emit({"type":"session_info_update","title":"Refresh complete"})
    """#
    try Data(source.utf8).write(to: executable)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: executable.path)
    return executable
}

/// Deadline-based with a ceiling far above any healthy wait: the suite runs in
/// parallel and spawns fake servers, so a short budget turns load into
/// failures. The ceiling exists to turn a hang into a failure, not to police
/// latency.
@MainActor
private func eventually(
    timeout: Duration = .seconds(30),
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
        timeout: Duration = .seconds(30)
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout.seconds)
        while Date() < deadline {
            if requestCount >= count { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return requestCount >= count
    }

    func waitForDelayedFailureCompletion(timeout: Duration = .seconds(30)) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout.seconds)
        while Date() < deadline {
            if didCompleteDelayedFailure { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return didCompleteDelayedFailure
    }
}

private actor CountingHistoryLoader {
    private(set) var requestCount = 0

    func load(path: String) async throws -> TranscriptHistory? {
        requestCount += 1
        return TranscriptHistory(items: [])
    }

    func waitForRequestCount(
        _ count: Int,
        timeout: Duration = .seconds(30)
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout.seconds)
        while Date() < deadline {
            if requestCount >= count { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return requestCount >= count
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
        timeout: Duration = .seconds(30)
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
        timeout: Duration = .seconds(30)
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

@MainActor @Test func idleEvictionEligibilityRequiresAnIdleSessionWithNothingUnsaved() async throws {
    let manager = fakeManager(mode: "basic")
    let clean = SessionController(processManager: manager, previewItems: [], runtimeState: .idle)
    #expect(clean.isEligibleForIdleEviction)

    let busyStates: [SessionRuntimeState] = [
        .loading, .streaming, .stopped(code: nil, stderrTail: ""), .failed("x"),
    ]
    for state in busyStates {
        let busy = SessionController(processManager: manager, previewItems: [], runtimeState: state)
        #expect(!busy.isEligibleForIdleEviction, "\(state) must not be reclaimable")
    }

    let drafted = SessionController(processManager: manager, previewItems: [], runtimeState: .idle)
    drafted.draft = "unsent"
    #expect(!drafted.isEligibleForIdleEviction)

    let attached = SessionController(processManager: manager, previewItems: [], runtimeState: .idle)
    attached.attachments = [ComposerAttachment(
        name: "shot.png", data: Data([0x89, 0x50]), mimeType: "image/png",
        pixelWidth: 1, pixelHeight: 1)]
    #expect(!attached.isEligibleForIdleEviction)

    let submitting = SessionController(processManager: manager, previewItems: [], runtimeState: .idle)
    submitting.prepareInitialSubmission(text: "Start", attachments: [])
    #expect(!submitting.isEligibleForIdleEviction)
}

@MainActor @Test func controllerHydratesItsOwnedDraftBeforeOpening() {
    let store = ComposerRecoveryStore.inMemory()
    let owner = ComposerRecoveryOwner.session("/tmp/recovered-session.jsonl")
    let attachment = ComposerAttachment(
        name: "saved.png", data: Data([1, 2, 3]), mimeType: "image/png",
        pixelWidth: 1, pixelHeight: 1)
    store.setDraft(
        ComposerRecoveryDraft(text: "saved text", attachments: [attachment]),
        for: owner)

    let controller = SessionController(
        processManager: SessionProcessManager(executable: "/usr/bin/false"),
        recoveryStore: store,
        recoveryOwner: owner)

    #expect(controller.draft == "saved text")
    #expect(controller.attachments == [attachment])
    controller.draft = "edited"
    #expect(store.record(for: owner)?.draft.text == "edited")
}

@MainActor @Test func recoveredInFlightIgnoresAnIdenticalMessageBeforeItsMinimumIndex() async throws {
    let manager = fakeManager(mode: "basic")
    let store = ComposerRecoveryStore.inMemory()
    let owner = ComposerRecoveryOwner.session("/tmp/recovery-no-echo.jsonl")
    store.setDraft(ComposerRecoveryDraft(text: "newer", attachments: []), for: owner)
    store.setInFlight(
        ComposerRecoveryInFlight(
            id: UUID(),
            draft: ComposerRecoveryDraft(text: "submitted", attachments: []),
            minimumUserIndex: 1),
        for: owner)
    let controller = SessionController(
        processManager: manager,
        historyLoader: { _ in TranscriptHistory(items: [recoveryUserItem("submitted")]) },
        recoveryStore: store,
        recoveryOwner: owner)

    await controller.openExisting(metadata(
        path: "/tmp/recovery-no-echo.jsonl", cwd: try temporaryDirectory().path))

    #expect(controller.draft == "submitted\n\nnewer")
    #expect(controller.composerRecoveryMessage
        == "A previous send wasn’t confirmed. Review the conversation before sending this draft.")
    #expect(store.record(for: owner)?.inFlight == nil)
    await manager.closeAll()
}

@MainActor @Test func recoveredInFlightIsDiscardedOnlyWhenHistoryContainsItsEchoAfterTheFence() async throws {
    let manager = fakeManager(mode: "basic")
    let store = ComposerRecoveryStore.inMemory()
    let owner = ComposerRecoveryOwner.session("/tmp/recovery-with-echo.jsonl")
    store.setDraft(ComposerRecoveryDraft(text: "newer", attachments: []), for: owner)
    store.setInFlight(
        ComposerRecoveryInFlight(
            id: UUID(),
            draft: ComposerRecoveryDraft(text: "submitted", attachments: []),
            minimumUserIndex: 1),
        for: owner)
    let controller = SessionController(
        processManager: manager,
        historyLoader: { _ in TranscriptHistory(items: [
            recoveryUserItem("submitted", id: "old"),
            recoveryUserItem("submitted", id: "echo"),
        ]) },
        recoveryStore: store,
        recoveryOwner: owner)

    await controller.openExisting(metadata(
        path: "/tmp/recovery-with-echo.jsonl", cwd: try temporaryDirectory().path))

    #expect(controller.draft == "newer")
    #expect(controller.composerRecoveryMessage == nil)
    #expect(store.record(for: owner)?.inFlight == nil)
    await manager.closeAll()
}

private func recoveryUserItem(_ text: String, id: String = "user") -> TranscriptItem {
    .message(TranscriptMessage(
        id: id,
        raw: .object([
            "id": .string(id),
            "role": .string("user"),
            "content": .array([.object([
                "type": .string("text"),
                "text": .string(text),
            ])]),
            "timestamp": .double(0),
        ]),
        isFinal: true))
}

@MainActor @Test func acceptedSendClearsOnlyInFlightRecoveryAndKeepsNewerInput() async throws {
    let manager = fakeManager(mode: "delayed-prompt-success")
    let store = ComposerRecoveryStore.inMemory()
    let controller = SessionController(
        processManager: manager,
        recoveryStore: store,
        recoveryOwner: .project(try temporaryDirectory()))
    await controller.openNew(projectURL: try temporaryDirectory())
    controller.draft = "submitted"
    controller.attachments = [controllerRecoveryAttachment(1)]

    let send = Task { await controller.sendPrompt() }
    #expect(await eventually { controller.runtimeState == .streaming })
    controller.draft = "newer"
    controller.attachments = [controllerRecoveryAttachment(2)]
    await send.value

    let owner = ComposerRecoveryOwner.session(try #require(controller.sessionPath))
    #expect(store.record(for: owner)?.draft.text == "newer")
    #expect(store.record(for: owner)?.draft.attachments.map(\.data) == [Data([2])])
    #expect(store.record(for: owner)?.inFlight == nil)
    await manager.closeAll()
}

@MainActor @Test func rejectedSendKeepsInFlightRecoveryAlongsideNewerInput() async throws {
    let manager = fakeManager(mode: "delayed-prompt-failure")
    let store = ComposerRecoveryStore.inMemory()
    let controller = SessionController(
        processManager: manager,
        recoveryStore: store,
        recoveryOwner: .project(try temporaryDirectory()))
    await controller.openNew(projectURL: try temporaryDirectory())
    controller.draft = "submitted"
    let submittedAttachment = controllerRecoveryAttachment(1)
    controller.attachments = [submittedAttachment]

    let send = Task { await controller.sendPrompt() }
    #expect(await eventually { controller.runtimeState == .streaming })
    controller.draft = "newer"
    controller.attachments = [controllerRecoveryAttachment(2)]
    await send.value

    let owner = ComposerRecoveryOwner.session(try #require(controller.sessionPath))
    #expect(store.record(for: owner)?.draft.text == "newer")
    #expect(store.record(for: owner)?.inFlight?.draft.text == "submitted")
    #expect(store.record(for: owner)?.inFlight?.draft.attachments == [submittedAttachment])
    await manager.closeAll()
}

@MainActor @Test func delayedInitialOpenTransfersOwnershipWithoutErasingNewerInput() async throws {
    let marker = try temporaryDirectory().appending(path: "opening")
    let manager = delayedFakeManager(mode: "basic", markerURL: marker)
    let store = ComposerRecoveryStore.inMemory()
    let project = try temporaryDirectory()
    let initialID = UUID()
    let controller = SessionController(
        processManager: manager,
        id: initialID,
        recoveryStore: store,
        recoveryOwner: .initial(id: initialID, projectURL: project))
    let submittedAttachment = controllerRecoveryAttachment(1)
    controller.prepareInitialSubmission(
        text: "submitted", attachments: [submittedAttachment], projectURL: project)

    let opening = Task { await controller.openNew(projectURL: project) }
    #expect(await eventually { FileManager.default.fileExists(atPath: marker.path) })
    controller.draft = "typed while opening"
    controller.attachments = [controllerRecoveryAttachment(2)]
    _ = await opening.value
    await controller.sendPrompt()

    let owner = ComposerRecoveryOwner.session(try #require(controller.sessionPath))
    #expect(store.initialRecords(for: project).isEmpty)
    #expect(store.record(for: owner)?.draft.text == "typed while opening")
    #expect(store.record(for: owner)?.draft.attachments.map(\.data) == [Data([2])])
    #expect(store.record(for: owner)?.inFlight == nil)
    await manager.closeAll()
}

private func controllerRecoveryAttachment(_ byte: UInt8) -> ComposerAttachment {
    ComposerAttachment(
        name: "\(byte).png", data: Data([byte]), mimeType: "image/png",
        pixelWidth: 1, pixelHeight: 1)
}
