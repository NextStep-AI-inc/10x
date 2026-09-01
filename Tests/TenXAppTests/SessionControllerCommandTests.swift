import Darwin
import Foundation
import OmpKit
import Testing
@testable import TenXApp

@MainActor
@Test func activeSessionLoadsAndReplacesAvailableCommands() async throws {
    let manager = commandFakeManager(mode: "catalog-update")
    let controller = SessionController(processManager: manager)
    var updates = controller.commandUpdates.makeAsyncIterator()
    let project = try commandTemporaryDirectory()
    defer { commandRemove(project) }
    let opening = Task { await controller.openNew(projectURL: project) }

    #expect(try #require(await updates.next()) == .loading)
    #expect(try #require(await updates.next()) == .available([
        AvailableSlashCommand(name: "compact", source: .builtin),
    ]))
    _ = await opening.value
    #expect(try #require(await updates.next()) == .available([
        AvailableSlashCommand(name: "retry", source: .builtin),
    ]))
    #expect(controller.commandCatalogState == .available([
        AvailableSlashCommand(name: "retry", source: .builtin),
    ]))
    #expect(controller.availableCommands == [
        AvailableSlashCommand(name: "retry", source: .builtin),
    ])
    await manager.closeAll()
}

@MainActor
@Test func staleSessionCommandUpdateCannotReplaceRestartedCatalog() async throws {
    let manager = commandFakeManager(mode: "delayed-catalog-update")
    let controller = SessionController(processManager: manager)
    let project = try commandTemporaryDirectory()
    defer { commandRemove(project) }

    await controller.openNew(projectURL: project)
    let staleFrame = try commandEvent(#"{"type":"available_commands_update","commands":[{"name":"stale","source":"builtin"}]}"#)
    let staleConsumer = try #require(controller.testingCapturedControlConsumer(staleFrame))
    await controller.restart()
    await staleConsumer()

    #expect(await commandEventually {
        controller.commandCatalogState == .available([
            AvailableSlashCommand(name: "compact", source: .builtin),
        ])
    })
    #expect(!controller.availableCommands.contains { $0.name == "stale" })
    await manager.closeAll()
}

@MainActor
@Test func unavailableCommandDiscoveryDoesNotFailTheSession() async throws {
    for mode in ["malformed-catalog", "unsupported-catalog"] {
        let manager = commandFakeManager(mode: mode)
        let controller = SessionController(processManager: manager)
        let project = try commandTemporaryDirectory()
        defer { commandRemove(project) }

        await controller.openNew(projectURL: project)

        #expect(controller.commandCatalogState == .unavailable)
        #expect(controller.runtimeState == .idle)
        #expect(controller.isComposerAvailable)
        await manager.closeAll()
    }
}

@MainActor
@Test func malformedCommandUpdateMakesTheCatalogUnavailable() async throws {
    let manager = commandFakeManager(mode: "malformed-catalog-update")
    let controller = SessionController(processManager: manager)
    let project = try commandTemporaryDirectory()
    defer { commandRemove(project) }

    await controller.openNew(projectURL: project)

    #expect(await commandEventually { controller.commandCatalogState == .unavailable })
    #expect(controller.runtimeState == .idle)
    await manager.closeAll()
}

@MainActor
@Test func stoppedAndFailedPipelinesMakeCommandsUnavailable() async throws {
    let stoppedManager = commandFakeManager(mode: "basic")
    let stoppedController = SessionController(processManager: stoppedManager)
    let stoppedProject = try commandTemporaryDirectory()
    defer { commandRemove(stoppedProject) }

    await stoppedController.openNew(projectURL: stoppedProject)
    stoppedController.handleUnexpectedExit(code: 9, stderrTail: "boom")
    #expect(stoppedController.commandCatalogState == .unavailable)
    await stoppedManager.closeAll()

    let failedManager = commandFakeManager(mode: "prompt-failure")
    let failedController = SessionController(processManager: failedManager)
    let failedProject = try commandTemporaryDirectory()
    defer { commandRemove(failedProject) }

    await failedController.openNew(projectURL: failedProject)
    failedController.draft = "prompt"
    await failedController.sendPrompt()
    #expect(failedController.commandCatalogState == .unavailable)
    await failedManager.closeAll()
}

@MainActor
@Test func openingANewPipelinePublishesLoadingBeforeItsCatalog() async throws {
    let manager = commandFakeManager(mode: "basic")
    let controller = SessionController(processManager: manager)
    var updates = controller.commandUpdates.makeAsyncIterator()
    let project = try commandTemporaryDirectory()
    defer { commandRemove(project) }
    let opening = Task { await controller.openNew(projectURL: project) }

    #expect(try #require(await updates.next()) == .loading)
    #expect(try #require(await updates.next()) == .available([]))
    _ = await opening.value
    await manager.closeAll()
}

@MainActor
@Test func startupCommandUpdateAppliesBeforeAndYieldsToInitialCatalogSnapshot() async throws {
    let manager = commandFakeManager(mode: "startup-catalog-update")
    let controller = SessionController(processManager: manager)
    var updates = controller.commandUpdates.makeAsyncIterator()
    let project = try commandTemporaryDirectory()
    defer { commandRemove(project) }
    let opening = Task { await controller.openNew(projectURL: project) }

    #expect(try #require(await updates.next()) == .loading)
    let startup = try #require(await updates.next())
    #expect(startup == .available([
        AvailableSlashCommand(name: "startup", source: .builtin),
    ]))
    let rpc = try #require(await updates.next())
    #expect(rpc == .available([
        AvailableSlashCommand(name: "rpc", source: .builtin),
    ]))
    _ = await opening.value
    #expect(controller.commandCatalogState == .available([
        AvailableSlashCommand(name: "rpc", source: .builtin),
    ]))
    #expect(controller.items.count == 1)
    guard case .threadStart = controller.items[0] else {
        Issue.record("Catalog control frames must not add transcript items")
        return
    }
    #expect(controller.runtimeState == .idle)
    await manager.closeAll()
}

@MainActor
@Test func startupCommandUpdateYieldsToUnsupportedInitialDiscovery() async throws {
    let manager = commandFakeManager(mode: "startup-unsupported-catalog")
    let controller = SessionController(processManager: manager)
    var updates = controller.commandUpdates.makeAsyncIterator()
    let project = try commandTemporaryDirectory()
    defer { commandRemove(project) }
    let opening = Task { await controller.openNew(projectURL: project) }

    #expect(try #require(await updates.next()) == .loading)
    #expect(try #require(await updates.next()) == .available([
        AvailableSlashCommand(name: "startup", source: .builtin),
    ]))
    #expect(try #require(await updates.next()) == .unavailable)
    _ = await opening.value
    #expect(controller.commandCatalogState == .unavailable)
    #expect(controller.runtimeState == .idle)
    await manager.closeAll()
}

@MainActor
@Test func restartPublishesLoadingBeforeItsReplacementPipelineOpens() async throws {
    let manager = commandFakeManager(mode: "basic")
    let controller = SessionController(processManager: manager)
    let project = try commandTemporaryDirectory()
    defer { commandRemove(project) }

    await controller.openNew(projectURL: project)
    let restarting = Task { await controller.restart() }
    await Task.yield()

    #expect(controller.commandCatalogState == .loading)
    await restarting.value
    await manager.closeAll()
}

@MainActor
@Test func closingDuringAnOpeningTaskPublishesUnavailable() async throws {
    let marker = FileManager.default.temporaryDirectory
        .appendingPathComponent("command-ready-pid-\(UUID().uuidString)")
    let manager = commandFakeManager(mode: "blocked-ready", readyPIDURL: marker)
    let controller = SessionController(processManager: manager)
    let project = try commandTemporaryDirectory()
    defer {
        commandRemove(project)
        commandRemove(marker)
    }
    let opening = Task { await controller.openNew(projectURL: project) }

    #expect(await commandEventually({
        controller.commandCatalogState == .loading
            && FileManager.default.fileExists(atPath: marker.path)
    }, timeout: .seconds(10)))
    let closing = try #require(controller.dispose())
    #expect(controller.commandCatalogState == .unavailable)
    let processID = try #require(Int32(String(contentsOf: marker, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
    #expect(kill(processID, SIGUSR1) == 0)
    await closing.value
    _ = await opening.value
    await manager.closeAll()
}

@MainActor
@Test func localSlashCommandKeepsAttachmentsAndReturnsIdle() async throws {
    let fixture = try await SlashControllerFixture(mode: "slash-local")
    defer { fixture.cleanupAfterFailure() }
    fixture.controller.draft = "/usage"
    fixture.controller.attachments = [fixture.firstAttachment]

    await fixture.controller.sendSlashCommand("/usage")

    #expect(fixture.controller.draft.isEmpty)
    #expect(fixture.controller.attachments.map(\.id) == [fixture.firstAttachment.id])
    #expect(fixture.controller.runtimeState == .idle)
    #expect(fixture.controller.items.count == 1)
    guard case .threadStart = fixture.controller.items[0] else {
        Issue.record("Local slash command should not add transcript prompt items")
        await fixture.cleanup()
        return
    }
    #expect(try fixture.recordedPrompt().message == "/usage")
    await fixture.cleanup()
}

@MainActor
@Test func agentSlashCommandClearsOnlyAcceptedAttachmentIdentities() async throws {
    let fixture = try await SlashControllerFixture(mode: "slash-agent")
    defer { fixture.cleanupAfterFailure() }
    fixture.controller.draft = "/skill:brainstorming plan it"
    fixture.controller.attachments = [fixture.firstAttachment]
    let send = Task {
        await fixture.controller.sendSlashCommand("/skill:brainstorming plan it")
    }
    #expect(await fixture.waitUntilPromptArrives())
    fixture.controller.attachments.append(fixture.secondAttachment)
    await send.value

    #expect(fixture.controller.attachments.map(\.id) == [fixture.secondAttachment.id])
    let prompt = try fixture.recordedPrompt()
    #expect(prompt.message == "/skill:brainstorming plan it")
    #expect(prompt.images.count == 1)
    let image = try #require(prompt.images.first)
    #expect(image.type == "image")
    #expect(image.mimeType == fixture.firstAttachment.mimeType)
    #expect(Data(base64Encoded: image.data) == fixture.firstAttachment.data)
    await fixture.cleanup()
}

@MainActor
@Test func legacyAgentLifecycleClearsPendingAttachments() async throws {
    let fixture = try await SlashControllerFixture(mode: "slash-legacy-agent")
    defer { fixture.cleanupAfterFailure() }
    fixture.controller.draft = "/compact"
    fixture.controller.attachments = [fixture.firstAttachment]

    await fixture.controller.sendSlashCommand("/compact")

    #expect(await commandEventually { fixture.controller.attachments.isEmpty })
    await fixture.cleanup()
}

@MainActor
@Test func legacyAgentLifecycleCanConfirmBeforePromptResponseResumes() async throws {
    let fixture = try await SlashControllerFixture(mode: "slash-event-before-response")
    defer { fixture.cleanupAfterFailure() }
    fixture.controller.draft = "/compact"
    fixture.controller.attachments = [fixture.firstAttachment]

    await fixture.controller.sendSlashCommand("/compact")

    #expect(fixture.controller.attachments.isEmpty)
    await fixture.cleanup()
}

@MainActor
@Test func lifecycleBeforeLocalSlashResponseDoesNotClearAttachments() async throws {
    let fixture = try await SlashControllerFixture(mode: "slash-event-before-local")
    defer { fixture.cleanupAfterFailure() }
    fixture.controller.draft = "/usage"
    fixture.controller.attachments = [fixture.firstAttachment]

    await fixture.controller.sendSlashCommand("/usage")

    #expect(fixture.controller.draft.isEmpty)
    #expect(fixture.controller.attachments.map(\.id) == [fixture.firstAttachment.id])
    #expect(fixture.controller.runtimeState == .idle)
    await fixture.cleanup()
}

@MainActor
@Test func lifecycleBeforeSlashFailureRestoresDraftAndAttachments() async throws {
    let fixture = try await SlashControllerFixture(mode: "slash-event-before-failure")
    defer { fixture.cleanupAfterFailure() }
    fixture.controller.draft = "/compact"
    fixture.controller.attachments = [fixture.firstAttachment]

    await fixture.controller.sendSlashCommand("/compact")

    #expect(fixture.controller.draft == "/compact")
    #expect(fixture.controller.attachments.map(\.id) == [fixture.firstAttachment.id])
    await fixture.cleanup()
}

@MainActor
@Test func slashCommandDuringStreamingAlwaysUsesFollowUp() async throws {
    let fixture = try await SlashControllerFixture(mode: "slash-streaming-record")
    defer { fixture.cleanupAfterFailure() }
    fixture.controller.draft = "start streaming"
    await fixture.controller.sendPrompt()
    #expect(await commandEventually { fixture.controller.runtimeState == .streaming })
    fixture.controller.selectStreamingBehavior(.steer)
    fixture.controller.draft = "/retry"

    await fixture.controller.sendSlashCommand("/retry")

    #expect(try fixture.recordedPrompt(at: 1).streamingBehavior == "followUp")
    #expect(fixture.controller.streamingBehavior == .steer)
    await fixture.cleanup()
}

@MainActor
@Test func slashTransportFailureRestoresDraftAndAttachments() async throws {
    let fixture = try await SlashControllerFixture(mode: "slash-failure")
    defer { fixture.cleanupAfterFailure() }
    fixture.controller.draft = "/compact"
    fixture.controller.attachments = [fixture.firstAttachment]

    await fixture.controller.sendSlashCommand("/compact")

    #expect(fixture.controller.draft == "/compact")
    #expect(fixture.controller.attachments.map(\.id) == [fixture.firstAttachment.id])
    await fixture.cleanup()
}

@MainActor
@Test func promptResultDropsPendingSlashWithoutClearingAttachments() async throws {
    let fixture = try await SlashControllerFixture(mode: "slash-prompt-result")
    defer { fixture.cleanupAfterFailure() }
    fixture.controller.draft = "/usage"
    fixture.controller.attachments = [fixture.firstAttachment]

    await fixture.controller.sendSlashCommand("/usage")

    #expect(await commandEventually { fixture.controller.runtimeState == .idle })
    #expect(fixture.controller.attachments.map(\.id) == [fixture.firstAttachment.id])
    await fixture.cleanup()
}

private func commandFakeManager(
    mode: String,
    readyPIDURL: URL? = nil,
    promptRecordURL: URL? = nil
) -> SessionProcessManager {
    SessionProcessManager(clientFactory: { configuration in
        var fake = configuration
        fake.executable = "/usr/bin/python3"
        fake.extraArguments = [commandFakeServerURL().path, mode]
        fake.rawArgv = true
        fake.cwd = nil
        var environment: [String: String] = [:]
        if let readyPIDURL {
            environment["OMP_FAKE_READY_PID"] = readyPIDURL.path
        }
        if let promptRecordURL {
            environment["OMP_FAKE_PROMPT_RECORD"] = promptRecordURL.path
        }
        if !environment.isEmpty {
            fake.environment = environment
        }
        return RpcClient(configuration: fake)
    })
}

private func commandFakeServerURL() -> URL {
    URL(filePath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/composer_fake_server.py")
}

private func commandTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("session-controller-command-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func commandRemove(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

private func commandEvent(_ json: String) throws -> RpcFrame {
    try RpcFrame.decode(line: Data(json.utf8))
}

@MainActor
private final class SlashControllerFixture {
    let controller: SessionController
    let manager: SessionProcessManager
    let project: URL
    let promptRecordURL: URL
    let firstAttachment = ComposerAttachment(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "one.png",
        data: Data([1, 2, 3]),
        mimeType: "image/png",
        pixelWidth: 1,
        pixelHeight: 1)
    let secondAttachment = ComposerAttachment(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "two.png",
        data: Data([4, 5, 6]),
        mimeType: "image/png",
        pixelWidth: 1,
        pixelHeight: 1)
    private var didCleanUp = false

    init(mode: String) async throws {
        let directory = try commandTemporaryDirectory()
        project = directory
        promptRecordURL = directory.appendingPathComponent("prompts.jsonl")
        manager = commandFakeManager(mode: mode, promptRecordURL: promptRecordURL)
        controller = SessionController(processManager: manager)
        await controller.openNew(projectURL: directory)
    }

    func cleanup() async {
        guard !didCleanUp else { return }
        didCleanUp = true
        await manager.closeAll()
        commandRemove(project)
    }

    func cleanupAfterFailure() {
        guard !didCleanUp else { return }
        Task { await manager.closeAll() }
        commandRemove(project)
    }

    func waitUntilPromptArrives() async -> Bool {
        await commandEventually({
            (try? String(contentsOf: promptRecordURL, encoding: .utf8).isEmpty) == false
        }, timeout: .seconds(5))
    }

    func recordedPrompt(at index: Int = 0) throws -> RecordedPrompt {
        let lines = try String(contentsOf: promptRecordURL, encoding: .utf8)
            .split(separator: "\n")
        let line = try #require(lines.indices.contains(index) ? String(lines[index]) : nil)
        return try JSONDecoder().decode(RecordedPrompt.self, from: Data(line.utf8))
    }
}

private struct RecordedPrompt: Decodable {
    let message: String
    let images: [RecordedPromptImage]
    let streamingBehavior: String?
}

private struct RecordedPromptImage: Decodable {
    let type: String
    let data: String
    let mimeType: String
}

@MainActor
private func commandEventually(
    _ condition: @MainActor () -> Bool,
    timeout: Duration = .seconds(2)
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition(), clock.now < deadline {
        await Task.yield()
    }
    return condition()
}
