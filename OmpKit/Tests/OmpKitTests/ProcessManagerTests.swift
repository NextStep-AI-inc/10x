import Testing
import Foundation
@testable import OmpKit

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

private final class CompletionFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func markCompleted() {
        lock.lock()
        value = true
        lock.unlock()
    }

    func isCompleted() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private func capturingManager(
    _ capture: ConfigurationCapture, mode: String = "basic"
) -> SessionProcessManager {
    SessionProcessManager(clientFactory: { configuration in
        capture.append(configuration)
        var fake = configuration
        fake.executable = "/usr/bin/env"
        fake.extraArguments = ["python3", fixtureURL("fake_server.py").path, mode]
        fake.rawArgv = true
        fake.cwd = nil
        return RpcClient(configuration: fake)
    })
}

private func fakeManager(mode: String = "basic") -> SessionProcessManager {
    SessionProcessManager(clientFactory: { configuration in
        var c = configuration
        c.executable = "/usr/bin/env"
        c.extraArguments = ["python3", fixtureURL("fake_server.py").path, mode]
        c.rawArgv = true
        return RpcClient(configuration: c)
    })
}

@Test func openIsIdempotentPerPath() async throws {
    let manager = fakeManager()
    let first = try await manager.open(sessionPath: "/tmp/s.jsonl", cwd: "/tmp")
    let second = try await manager.open(sessionPath: "/tmp/s.jsonl", cwd: "/tmp")
    #expect(first.client === second.client)
    await manager.closeAll()
}

@Test func concurrentOpenSharesOneChild() async throws {
    let capture = ConfigurationCapture()
    let manager = capturingManager(capture)
    async let first = manager.open(sessionPath: "/tmp/shared.jsonl", cwd: "/tmp/project")
    async let second = manager.open(sessionPath: "/tmp/shared.jsonl", cwd: "/tmp/project")
    let handles = try await [first, second]
    #expect(handles[0].client === handles[1].client)
    #expect(capture.snapshot().count == 1)
    await manager.closeAll()
}

@Test func managerForwardsResumePathAndWorkingDirectory() async throws {
    let capture = ConfigurationCapture()
    let manager = capturingManager(capture)
    _ = try await manager.open(
        sessionPath: "/tmp/session.jsonl", cwd: "/tmp/project")
    let configuration = capture.snapshot().first
    #expect(configuration?.resumeSessionPath == "/tmp/session.jsonl")
    #expect(configuration?.cwd?.path == "/tmp/project")
    #expect(configuration?.rawArgv == false)
    #expect(configuration?.resolvedArguments == [
        "--mode", "rpc", "--no-title", "-r", "/tmp/session.jsonl",
    ])
    await manager.closeAll()
}

@Test func managerForwardsConfiguredExecutable() async throws {
    let capture = ConfigurationCapture()
    let manager = SessionProcessManager(
        executable: "/Applications/10x Support/omp",
        clientFactory: { configuration in
            capture.append(configuration)
            var fake = configuration
            fake.executable = "/usr/bin/env"
            fake.extraArguments = ["python3", fixtureURL("fake_server.py").path, "basic"]
            fake.rawArgv = true
            fake.cwd = nil
            return RpcClient(configuration: fake)
        })

    _ = try await manager.openNew(projectDirectory: "/tmp/project")

    #expect(capture.snapshot().first?.executable == "/Applications/10x Support/omp")
    await manager.closeAll()
}

@Test func openNewForwardsProviderModelThinkingFlags() async throws {
    let capture = ConfigurationCapture()
    let manager = capturingManager(capture, mode: "no-session-file")
    _ = try await manager.openNew(
        projectDirectory: "/tmp/project",
        provider: "anthropic",
        model: "claude-opus-4-8",
        thinking: "high")
    let configuration = capture.snapshot().first
    #expect(configuration?.provider == "anthropic")
    #expect(configuration?.model == "claude-opus-4-8")
    #expect(configuration?.thinking == "high")
    #expect(configuration?.resolvedArguments == [
        "--mode", "rpc", "--no-title",
        "--provider", "anthropic",
        "--model", "claude-opus-4-8",
        "--thinking", "high",
    ])
    await manager.closeAll()
}

@Test func openNewForwardsWorkingDirectoryAndUsesUniqueFallbackKeys() async throws {
    let capture = ConfigurationCapture()
    let manager = capturingManager(capture, mode: "no-session-file")
    let first = try await manager.openNew(projectDirectory: "/tmp/project")
    let second = try await manager.openNew(projectDirectory: "/tmp/project")
    #expect(first.sessionPath != second.sessionPath)
    let configurations = capture.snapshot()
    #expect(configurations.count == 2)
    #expect(configurations.allSatisfy { $0.cwd?.path == "/tmp/project" })
    #expect(configurations.allSatisfy { $0.resumeSessionPath == nil })
    await manager.closeAll()
}

@Test func closeRemovesTheHandle() async throws {
    let manager = fakeManager()
    _ = try await manager.open(sessionPath: "/tmp/gone.jsonl", cwd: "/tmp")
    #expect(await manager.handle(for: "/tmp/gone.jsonl") != nil)
    await manager.close(sessionPath: "/tmp/gone.jsonl")
    #expect(await manager.handle(for: "/tmp/gone.jsonl") == nil)
}

@Test func closeCancelsAnInflightOpenBeforeItCanRegisterAHandle() async throws {
    let capture = ConfigurationCapture()
    let completion = CompletionFlag()
    let manager = SessionProcessManager(clientFactory: { configuration in
        capture.append(configuration)
        var fake = configuration
        fake.executable = "/usr/bin/env"
        fake.extraArguments = ["python3", fixtureURL("fake_server.py").path, "never-ready"]
        fake.rawArgv = true
        fake.cwd = nil
        fake.startupTimeout = .milliseconds(800)
        return RpcClient(configuration: fake)
    })
    let openTask = Task {
        defer { completion.markCompleted() }
        return try? await manager.open(sessionPath: "/tmp/opening.jsonl", cwd: "/tmp")
    }
    while capture.snapshot().isEmpty { await Task.yield() }

    await manager.close(sessionPath: "/tmp/opening.jsonl")
    try await Task.sleep(for: .milliseconds(200))

    #expect(completion.isCompleted())
    #expect(await manager.handle(for: "/tmp/opening.jsonl") == nil)
    _ = await openTask.value
}

@Test func closeOfAnInflightOpenDoesNotDiscardANewerOpenForTheSamePath() async throws {
    let capture = ConfigurationCapture()
    let manager = SessionProcessManager(clientFactory: { configuration in
        capture.append(configuration)
        var fake = configuration
        fake.executable = "/usr/bin/env"
        let mode = capture.snapshot().count == 1 ? "never-ready" : "basic"
        fake.extraArguments = ["python3", fixtureURL("fake_server.py").path, mode]
        fake.rawArgv = true
        fake.cwd = nil
        fake.startupTimeout = .milliseconds(800)
        return RpcClient(configuration: fake)
    })
    let path = "/tmp/reopened.jsonl"
    let staleOpen = Task { try? await manager.open(sessionPath: path, cwd: "/tmp") }
    while capture.snapshot().isEmpty { await Task.yield() }

    let closeTask = Task { await manager.close(sessionPath: path) }
    try await Task.sleep(for: .milliseconds(20))
    let reopened = try? await manager.open(sessionPath: path, cwd: "/tmp")
    await closeTask.value

    #expect(await staleOpen.value == nil)
    #expect(reopened != nil)
    #expect(capture.snapshot().count == 2)
    #expect(await manager.handle(for: path)?.client === reopened?.client)
    await manager.closeAll()
}

@Test func distinctPathsGetDistinctChildren() async throws {
    let manager = fakeManager()
    let a = try await manager.open(sessionPath: "/tmp/a.jsonl", cwd: "/tmp")
    let b = try await manager.open(sessionPath: "/tmp/b.jsonl", cwd: "/tmp")
    #expect(a.client !== b.client)
    await manager.closeAll()
}

@Test func unexpectedExitIsSurfaced() async throws {
    let manager = fakeManager(mode: "crash-after-negotiation")
    let handle = try await manager.open(sessionPath: "/tmp/dies.jsonl", cwd: "/tmp")
    let stream = manager.unexpectedExits

    let event = await withTimeout(.seconds(5)) { () -> SessionProcessManager.UnexpectedExit? in
        for await exit in stream { return exit }
        return nil
    } ?? nil
    #expect(event?.sessionPath == "/tmp/dies.jsonl")
    #expect(event?.code == 7)
    #expect(event?.stderrTail.contains("crash-after-negotiation") == true)
    #expect(await manager.handle(for: handle.sessionPath) == nil)
    await manager.closeAll()
}

@Test func managerDoesNotConsumeApplicationEvents() async throws {
    let manager = fakeManager(mode: "burst")
    let handle = try await manager.open(sessionPath: "/tmp/burst.jsonl", cwd: "/tmp")
    let stream = handle.client.events
    let driver = Task {
        _ = try? await handle.client.send(.prompt(message: "go", streamingBehavior: nil))
    }
    defer { driver.cancel() }

    let count = await withTimeout(.seconds(5)) { () -> Int in
        var count = 0
        for await frame in stream {
            if case .event(let type, _) = frame, type == "message_update" { count += 1 }
            if count == 100 { break }
        }
        return count
    } ?? 0
    #expect(count == 100)
    await manager.closeAll()
}

@Test func deliberateCloseDoesNotReportAnExit() async throws {
    let manager = fakeManager()
    _ = try await manager.open(sessionPath: "/tmp/quiet.jsonl", cwd: "/tmp")
    let stream = manager.unexpectedExits
    await manager.close(sessionPath: "/tmp/quiet.jsonl")

    // No event should arrive; the timeout expiring is the passing outcome.
    let path = await withTimeout(.seconds(1)) { () -> String? in
        for await exit in stream { return exit.sessionPath }
        return nil
    } ?? nil
    #expect(path == nil)
}
