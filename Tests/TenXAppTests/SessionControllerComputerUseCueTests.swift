import Foundation
import OmpKit
import Testing
@testable import TenXApp

@MainActor
@Test func sendComputerUseCueWhileIdleUsesNextTurnAndLeavesDraftUntouched() async throws {
    let fixture = try await ComputerUseCueFixture(mode: "basic")
    defer { fixture.cleanupAfterFailure() }
    fixture.controller.draft = "keep this draft"

    await fixture.controller.sendComputerUseCue()

    let recorded = try fixture.recordedCustom()
    #expect(recorded.customType == "computer-use")
    #expect(recorded.content == SessionController.computerUseCueContent)
    #expect(recorded.display == false)
    #expect(recorded.deliverAs == "nextTurn")
    #expect(recorded.triggerTurn == nil)
    #expect(fixture.controller.draft == "keep this draft")
    #expect(fixture.controller.runtimeState == .idle)
    await fixture.cleanup()
}

@MainActor
@Test func sendComputerUseCueWhileStreamingUsesSteer() async throws {
    let fixture = try await ComputerUseCueFixture(mode: "slow-turn")
    defer { fixture.cleanupAfterFailure() }
    fixture.controller.draft = "start streaming"
    await fixture.controller.sendPrompt()
    #expect(await computerUseCueEventually { fixture.controller.runtimeState == .streaming })

    await fixture.controller.sendComputerUseCue()

    let recorded = try fixture.recordedCustom()
    #expect(recorded.deliverAs == "steer")
    #expect(fixture.controller.draft == "")
    await fixture.cleanup()
}

@MainActor
@Test func sendComputerUseCueFailureIsSwallowed() async throws {
    let fixture = try await ComputerUseCueFixture(mode: "custom-failure")
    defer { fixture.cleanupAfterFailure() }
    fixture.controller.draft = "unchanged"

    await fixture.controller.sendComputerUseCue()

    #expect(try fixture.recordedCustom().deliverAs == "nextTurn")
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
    let customRecordURL: URL
    private var didCleanUp = false

    init(mode: String) async throws {
        let directory = try computerUseCueTemporaryDirectory()
        project = directory
        customRecordURL = directory.appendingPathComponent("custom.jsonl")
        manager = computerUseCueFakeManager(mode: mode, customRecordURL: customRecordURL)
        controller = SessionController(processManager: manager)
        await controller.openNew(projectURL: directory)
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

    func recordedCustom() throws -> RecordedCustomCommand {
        try decodeRecordedCustom(from: customRecordURL)
    }
}

private struct RecordedCustomCommand: Decodable, Equatable {
    let customType: String?
    let content: String?
    let display: Bool?
    let deliverAs: String?
    let triggerTurn: Bool?
}

private func decodeRecordedCustom(from url: URL) throws -> RecordedCustomCommand {
    let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
    let line = try #require(lines.last.map(String.init))
    return try JSONDecoder().decode(RecordedCustomCommand.self, from: Data(line.utf8))
}

private func computerUseCueFakeManager(
    mode: String,
    customRecordURL: URL
) -> SessionProcessManager {
    SessionProcessManager(clientFactory: { configuration in
        var fake = configuration
        fake.executable = "/usr/bin/env"
        fake.extraArguments = [
            "python3",
            computerUseCueRepositoryRoot()
                .appending(path: "OmpKit/Tests/OmpKitTests/Fixtures/fake_server.py").path,
            mode,
        ]
        fake.rawArgv = true
        fake.cwd = nil
        fake.environment = ["OMP_FAKE_CUSTOM_RECORD": customRecordURL.path]
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
