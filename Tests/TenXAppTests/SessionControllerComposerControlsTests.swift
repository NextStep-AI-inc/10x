import Foundation
import OmpKit
import Testing
@testable import TenXApp

@MainActor
@Test func openNewForwardsSpawnFlagsAndSendsSetFastModeWhenRequested() async throws {
    let capture = ConfigurationCapture()
    let recordURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("composer-record-\(UUID().uuidString).txt")
    defer { try? FileManager.default.removeItem(at: recordURL) }
    let manager = composerCapturingManager(capture, recordURL: recordURL)
    let controller = SessionController(processManager: manager)
    let project = URL(filePath: "/tmp/composer-project", directoryHint: .isDirectory)
    let selection = ComposerSpawnSelection(
        provider: "anthropic",
        modelID: "claude-opus-4-8",
        thinking: "high",
        fastModeEnabled: true)

    await controller.openNew(projectURL: project, selection: selection)

    let configuration = try #require(capture.snapshot().first)
    #expect(configuration.provider == "anthropic")
    #expect(configuration.model == "claude-opus-4-8")
    #expect(configuration.thinking == "high")
    #expect(configuration.cwd?.path == project.path)
    let recorded = try String(contentsOf: recordURL, encoding: .utf8)
        .split(separator: "\n", omittingEmptySubsequences: true)
        .map(String.init)
    #expect(recorded.contains("set_fast_mode"))
    #expect(controller.sessionPath == "/tmp/fake.jsonl")
    await manager.closeAll()
}

@MainActor
@Test func openNewSkipsSetFastModeWhenFastIntentIsOff() async throws {
    let capture = ConfigurationCapture()
    let recordURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("composer-record-\(UUID().uuidString).txt")
    defer { try? FileManager.default.removeItem(at: recordURL) }
    let manager = composerCapturingManager(capture, recordURL: recordURL)
    let controller = SessionController(processManager: manager)
    let selection = ComposerSpawnSelection(
        provider: "anthropic",
        modelID: "claude-opus-4-8",
        thinking: "auto",
        fastModeEnabled: false)

    await controller.openNew(
        projectURL: URL(filePath: "/tmp/composer-project", directoryHint: .isDirectory),
        selection: selection)

    let recorded = try String(contentsOf: recordURL, encoding: .utf8)
        .split(separator: "\n", omittingEmptySubsequences: true)
        .map(String.init)
    #expect(!recorded.contains("set_fast_mode"))
    await manager.closeAll()
}

@MainActor
@Test func setModelUpdatesLabelFromResponse() async throws {
    let manager = composerManager(mode: "set-model-echo")
    let controller = SessionController(processManager: manager)
    await controller.openNew(
        projectURL: URL(filePath: "/tmp/composer-project", directoryHint: .isDirectory),
        selection: nil)

    try await controller.setModel(provider: "anthropic", modelID: "claude-sonnet-4-5")

    #expect(controller.modelName == "claude-sonnet-4-5")
    await manager.closeAll()
}

@MainActor
@Test func setThinkingLevelUpdatesLabel() async throws {
    let manager = composerManager(mode: "basic")
    let controller = SessionController(processManager: manager)
    await controller.openNew(
        projectURL: URL(filePath: "/tmp/composer-project", directoryHint: .isDirectory),
        selection: nil)

    try await controller.setThinkingLevel("high")

    #expect(controller.thinkingLevel == "High")
    await manager.closeAll()
}

@MainActor
@Test func setFastModeReturnsFalseWhenUnsupported() async throws {
    let manager = composerManager(mode: "fast-unsupported")
    let controller = SessionController(processManager: manager)
    await controller.openNew(
        projectURL: URL(filePath: "/tmp/composer-project", directoryHint: .isDirectory),
        selection: nil)

    let supported = try await controller.setFastMode(true)

    #expect(supported == false)
    await manager.closeAll()
}

@MainActor
@Test func setFastModeThrowsOnRpcFailure() async throws {
    let manager = composerManager(mode: "fast-rpc-fail")
    let controller = SessionController(processManager: manager)
    await controller.openNew(
        projectURL: URL(filePath: "/tmp/composer-project", directoryHint: .isDirectory),
        selection: nil)

    await #expect(throws: RpcClientError.self) {
        _ = try await controller.setFastMode(true)
    }
    await manager.closeAll()
}

@MainActor
@Test func setFastModeReturnsTrueWhenSupported() async throws {
    let manager = composerManager(mode: "basic")
    let controller = SessionController(processManager: manager)
    await controller.openNew(
        projectURL: URL(filePath: "/tmp/composer-project", directoryHint: .isDirectory),
        selection: nil)

    let supported = try await controller.setFastMode(true)

    #expect(supported == true)
    await manager.closeAll()
}

@MainActor
@Test func sessionControllerConformsToComposerSessionControlling() async throws {
    let manager = composerManager(mode: "basic")
    let controller = SessionController(processManager: manager)
    await controller.openNew(
        projectURL: URL(filePath: "/tmp/composer-project", directoryHint: .isDirectory),
        selection: nil)
    let bridge: any ComposerSessionControlling = controller

    try await bridge.setModel(provider: "anthropic", modelID: "claude-opus-4-8")
    try await bridge.setThinkingLevel("low")
    let supported = try await bridge.setFastMode(false)

    #expect(supported == true)
    await manager.closeAll()
}

// MARK: - Helpers

private final class ConfigurationCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [RpcClientConfiguration] = []

    func append(_ value: RpcClientConfiguration) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    func snapshot() -> [RpcClientConfiguration] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

private func composerCapturingManager(
    _ capture: ConfigurationCapture,
    recordURL: URL,
    mode: String = "basic"
) -> SessionProcessManager {
    SessionProcessManager(clientFactory: { configuration in
        capture.append(configuration)
        return makeComposerClient(configuration: configuration, mode: mode, recordURL: recordURL)
    })
}

private func composerManager(mode: String) -> SessionProcessManager {
    SessionProcessManager(clientFactory: { configuration in
        makeComposerClient(configuration: configuration, mode: mode, recordURL: nil)
    })
}

private func makeComposerClient(
    configuration: RpcClientConfiguration,
    mode: String,
    recordURL: URL?
) -> RpcClient {
    var fake = configuration
    fake.executable = "/usr/bin/python3"
    fake.extraArguments = [composerFakeServerURL().path, mode]
    fake.rawArgv = true
    fake.cwd = nil
    if let recordURL {
        fake.environment = ["OMP_FAKE_RECORD": recordURL.path]
    }
    return RpcClient(configuration: fake)
}

private func composerFakeServerURL() -> URL {
    URL(filePath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/composer_fake_server.py")
}
