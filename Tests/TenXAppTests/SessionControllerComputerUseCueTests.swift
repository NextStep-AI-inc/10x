import Foundation
import OmpKit
import Testing
@testable import TenXApp

@MainActor
@Test func sendComputerUsePromptWhileIdleSendsWrappedVisiblePrompt() async throws {
    let fixture = try await ComputerUseCueFixture(mode: "basic", recordsPrompts: true)
    defer { fixture.cleanupAfterFailure() }
    fixture.controller.draft = "keep this draft"

    await fixture.controller.sendComputerUsePrompt("check my email")

    #expect(await fixture.waitUntilPromptArrives())
    let prompt = try fixture.recordedPrompt()
    #expect(prompt.message == ComputerUsePrompt.wrap("check my email"))
    #expect(prompt.streamingBehavior == nil)
    #expect(await fixture.sentCommands().isEmpty)
    #expect(fixture.controller.draft.isEmpty)
    await fixture.cleanup()
}

@MainActor
@Test func sendComputerUsePromptWhileStreamingUsesFollowUpAndSkipsExtensionCue() async throws {
    let fixture = try await ComputerUseCueFixture(mode: "slash-streaming-record", recordsPrompts: true)
    defer { fixture.cleanupAfterFailure() }
    fixture.controller.draft = "start streaming"
    await fixture.controller.sendPrompt()
    #expect(await computerUseCueEventually { fixture.controller.runtimeState == .streaming })
    fixture.controller.selectStreamingBehavior(.steer)
    fixture.controller.draft = "keep this draft while streaming"

    await fixture.controller.sendComputerUsePrompt("check my email")

    #expect(await fixture.waitUntilPromptArrives())
    let prompt = try fixture.recordedPrompt(at: 1)
    #expect(prompt.message == ComputerUsePrompt.wrap("check my email"))
    #expect(prompt.streamingBehavior == "followUp")
    #expect(await fixture.sentCommands().isEmpty)
    #expect(fixture.controller.draft.isEmpty)
    await fixture.cleanup()
}

@MainActor
@Test func sendComputerUseCueWhileIdleSendsOneCommandAndLeavesDraftUntouched() async throws {
    let fixture = try await ComputerUseCueFixture(mode: "basic")
    defer { fixture.cleanupAfterFailure() }
    fixture.controller.draft = "keep this draft"

    await fixture.controller.sendComputerUseCue()

    let sent = await fixture.sentCommands()
    #expect(sent.count == 1)
    #expect(sent[0].command == "computer_use_cue")
    #expect(sent[0].params.isEmpty)
    #expect(fixture.controller.draft == "keep this draft")
    #expect(fixture.controller.runtimeState == .idle)
    await fixture.cleanup()
}

@MainActor
@Test func sendComputerUseCueWhileStreamingSendsOneCommandAndLeavesDraftUntouched() async throws {
    let fixture = try await ComputerUseCueFixture(mode: "slow-turn")
    defer { fixture.cleanupAfterFailure() }
    fixture.controller.draft = "start streaming"
    await fixture.controller.sendPrompt()
    #expect(await computerUseCueEventually { fixture.controller.runtimeState == .streaming })
    fixture.controller.draft = "keep this draft while streaming"

    await fixture.controller.sendComputerUseCue()

    let sent = await fixture.sentCommands()
    #expect(sent.count == 1)
    #expect(sent[0].command == "computer_use_cue")
    #expect(fixture.controller.draft == "keep this draft while streaming")
    await fixture.cleanup()
}

@MainActor
@Test func sendComputerUseCueFailureIsSwallowed() async throws {
    let fixture = try await ComputerUseCueFixture(mode: "basic", channel: FailingComputerUseCueChannel())
    defer { fixture.cleanupAfterFailure() }
    fixture.controller.draft = "unchanged"

    await fixture.controller.sendComputerUseCue()

    #expect(fixture.controller.draft == "unchanged")
    #expect(fixture.controller.runtimeState == .idle)
    #expect(!fixture.controller.isRecoveryPresented)
    await fixture.cleanup()
}

@MainActor
private final class ComputerUseCueFixture {
    let controller: SessionController
    let manager: SessionProcessManager
    let project: URL
    private let recordingChannel: RecordingComputerUseCueChannel?
    private let registry: ProviderAccountChannelRegistry
    private let promptRecordURL: URL?
    private var didCleanUp = false

    init(
        mode: String,
        channel: (any ProviderAccountChannel)? = nil,
        recordsPrompts: Bool = false
    ) async throws {
        let directory = try computerUseCueTemporaryDirectory()
        project = directory
        promptRecordURL = recordsPrompts
            ? directory.appendingPathComponent("prompts.jsonl")
            : nil
        manager = computerUseCueFakeManager(mode: mode, promptRecordURL: promptRecordURL)
        registry = ProviderAccountChannelRegistry()
        let recording = channel == nil ? RecordingComputerUseCueChannel() : nil
        recordingChannel = recording
        let attachedChannel = channel ?? recording!
        controller = SessionController(
            processManager: manager,
            accountChannelRegistry: registry)
        await controller.openNew(projectURL: directory)
        registry.attach(sessionID: controller.id, channel: attachedChannel, sessionFile: nil)
    }

    func sentCommands() async -> [ProviderAccountChannelCommand] {
        await recordingChannel?.sentCommands() ?? []
    }

    func waitUntilPromptArrives() async -> Bool {
        guard let promptRecordURL else { return false }
        return await computerUseCueEventually({
            (try? String(contentsOf: promptRecordURL, encoding: .utf8).isEmpty) == false
        })
    }

    func recordedPrompt(at index: Int = 0) throws -> ComputerUseRecordedPrompt {
        guard let promptRecordURL else {
            throw ComputerUsePromptRecordError.missingRecordFile
        }
        let lines = try String(contentsOf: promptRecordURL, encoding: .utf8)
            .split(separator: "\n")
        let line = try #require(lines.indices.contains(index) ? String(lines[index]) : nil)
        return try JSONDecoder().decode(ComputerUseRecordedPrompt.self, from: Data(line.utf8))
    }

    func cleanup() async {
        guard !didCleanUp else { return }
        didCleanUp = true
        await manager.closeAll()
        computerUseCueRemove(project)
    }

    func cleanupAfterFailure() {
        guard !didCleanUp else { return }
        Task { await manager.closeAll() }
        computerUseCueRemove(project)
    }
}

private actor RecordingComputerUseCueChannel: ProviderAccountChannel {
    private var commands: [ProviderAccountChannelCommand] = []

    func send(_ command: ProviderAccountChannelCommand) async throws -> JSONValue {
        commands.append(command)
        return .object(["delivered": .bool(true)])
    }

    func sentCommands() -> [ProviderAccountChannelCommand] {
        commands
    }
}

private actor FailingComputerUseCueChannel: ProviderAccountChannel {
    func send(_ command: ProviderAccountChannelCommand) async throws -> JSONValue {
        throw ProviderAccountChannelError.unavailable
    }
}

private func computerUseCueFakeManager(
    mode: String,
    promptRecordURL: URL? = nil
) -> SessionProcessManager {
    SessionProcessManager(clientFactory: { configuration in
        var fake = configuration
        fake.executable = "/usr/bin/python3"
        let serverURL = promptRecordURL == nil
            ? computerUseCueRepositoryRoot()
                .appending(path: "OmpKit/Tests/OmpKitTests/Fixtures/fake_server.py")
            : computerUseCueRepositoryRoot()
                .appending(path: "Tests/TenXAppTests/Fixtures/composer_fake_server.py")
        fake.extraArguments = [serverURL.path, mode]
        fake.rawArgv = true
        fake.cwd = nil
        if let promptRecordURL {
            fake.environment = ["OMP_FAKE_PROMPT_RECORD": promptRecordURL.path]
        }
        return RpcClient(configuration: fake)
    })
}

private func computerUseCueRepositoryRoot() -> URL {
    URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func computerUseCueTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "tenx-computer-use-cue-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func computerUseCueRemove(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

private func computerUseCueEventually(
    _ predicate: @escaping @MainActor () -> Bool,
    timeout: Duration = .seconds(5)
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await MainActor.run(body: predicate) { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await MainActor.run(body: predicate)
}

private struct ComputerUseRecordedPrompt: Decodable {
    let message: String
    let streamingBehavior: String?
}

private enum ComputerUsePromptRecordError: Error {
    case missingRecordFile
}
