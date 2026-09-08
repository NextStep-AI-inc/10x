import Testing
import Foundation
@testable import OmpKit

actor ActivationGate {
    private var entered = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func markEntered() {
        entered = true
        let waiters = self.waiters
        self.waiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func waitUntilReleased() async {
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func release() {
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
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

@Test func managerForwardsExtraArgumentsOnOpen() async throws {
    let capture = ConfigurationCapture()
    let manager = SessionProcessManager(
        extraArguments: ["-e", "/fake/ext/index.ts"],
        clientFactory: { configuration in
            capture.append(configuration)
            var fake = configuration
            fake.executable = "/usr/bin/env"
            fake.extraArguments = ["python3", fixtureURL("fake_server.py").path, "basic"]
            fake.rawArgv = true
            fake.cwd = nil
            return RpcClient(configuration: fake)
        })

    _ = try await manager.open(sessionPath: "/tmp/extra-args.jsonl", cwd: "/tmp/project")

    #expect(capture.snapshot().first?.extraArguments == ["-e", "/fake/ext/index.ts"])
    await manager.closeAll()
}

@Test func managerDefaultsToNoninteractiveRPCMode() async throws {
    let capture = ConfigurationCapture()
    let manager = capturingManager(capture)

    _ = try await manager.open(sessionPath: "/tmp/noninteractive.jsonl", cwd: "/tmp/project")

    #expect(capture.snapshot().first?.supportsUserInteraction == false)
    await manager.closeAll()
}

@Test func interactiveManagerForwardsCapabilityToOpenNewAndWarmClients() async throws {
    let openCapture = ConfigurationCapture()
    let openManager = interactiveCapturingManager(openCapture)
    _ = try await openManager.open(sessionPath: "/tmp/interactive.jsonl", cwd: "/tmp/project")
    #expect(openCapture.snapshot().first?.supportsUserInteraction == true)
    await openManager.closeAll()

    let newCapture = ConfigurationCapture()
    let newManager = interactiveCapturingManager(newCapture)
    _ = try await newManager.openNew(projectDirectory: "/tmp/project")
    #expect(newCapture.snapshot().first?.supportsUserInteraction == true)
    await newManager.closeAll()

    let warmCapture = ConfigurationCapture()
    let warmManager = interactiveCapturingManager(warmCapture)
    _ = try await warmManager.warm(projectDirectory: "/tmp/project")
    #expect(warmCapture.snapshot().first?.supportsUserInteraction == true)
    await warmManager.closeAll()
}

private func interactiveCapturingManager(
    _ capture: ConfigurationCapture
) -> SessionProcessManager {
    SessionProcessManager(
        supportsUserInteraction: true,
        clientFactory: { configuration in
            capture.append(configuration)
            var fake = configuration
            fake.executable = "/usr/bin/env"
            fake.extraArguments = ["python3", fixtureURL("fake_server.py").path, "basic"]
            fake.rawArgv = true
            fake.cwd = nil
            return RpcClient(configuration: fake)
        })
}

@Test func openNewForwardsProviderModelThinkingFlags() async throws {
    let capture = ConfigurationCapture()
    let manager = capturingManager(capture)
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
        "--session-dir", expectedFreshSessionDirectory(for: "/tmp/project"),
    ])
    await manager.closeAll()
}

@Test func coldOpenNewStartsFreshAndPersisted() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ProcessManager-\(UUID().uuidString)", isDirectory: true)
    let commandLog = root.appendingPathComponent("commands.log")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: commandLog.path, contents: nil)
    defer { try? FileManager.default.removeItem(at: root) }

    let capture = ConfigurationCapture()
    let manager = capturingManager(
        capture,
        mode: "command-log",
        modeArguments: [commandLog.path])
    _ = try await manager.openNew(projectDirectory: root.path)

    let configuration = capture.snapshot().first
    #expect(configuration?.noSession == false)
    #expect(configuration?.resolvedArguments == [
        "--mode", "rpc", "--no-title",
        "--session-dir",
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".omp/agent/sessions")
            .appendingPathComponent(SessionPathEncoding.bucketName(forCwd: root.path))
            .path,
    ])
    let commands = try String(contentsOf: commandLog, encoding: .utf8)
        .split(separator: "\n")
        .map(String.init)
    #expect(commands == ["negotiate_protocol", "get_state"])
    await manager.closeAll()
}

@Test func openNewRejectsAnUnpersistedSession() async {
    let clients = ClientCapture()
    let manager = SessionProcessManager(clientFactory: { configuration in
        var fake = configuration
        fake.executable = "/usr/bin/env"
        fake.extraArguments = ["python3", fixtureURL("fake_server.py").path, "no-session-file"]
        fake.rawArgv = true
        fake.cwd = nil
        let client = RpcClient(configuration: fake)
        clients.append(client)
        return client
    })
    await #expect(throws: SessionProcessManagerError.self) {
        _ = try await manager.openNew(projectDirectory: "/tmp/project")
    }
    #expect(await clients.snapshot().first?.exitCode != nil)
}

@Test func twoColdSessionsInOneProjectKeepDistinctRuntimeOwners() async throws {
    let capture = ConfigurationCapture()
    let manager = capturingManager(capture, mode: "unique-session-file")
    let first = try await manager.openNew(projectDirectory: "/tmp/project")
    let second = try await manager.openNew(projectDirectory: "/tmp/project")

    #expect(first.sessionPath != second.sessionPath)
    #expect(first.client !== second.client)
    #expect(await manager.handle(for: first.sessionPath)?.client === first.client)
    #expect(await manager.handle(for: second.sessionPath)?.client === second.client)
    #expect(capture.snapshot().allSatisfy { configuration in
        configuration.noSession == false
            && configuration.extraArguments == [
                "--session-dir",
                expectedFreshSessionDirectory(for: "/tmp/project"),
            ]
    })
    await manager.closeAll()
}

@Test func duplicateNewSessionPathPreservesTheExistingOwner() async throws {
    let clients = ClientCapture()
    let manager = SessionProcessManager(clientFactory: { configuration in
        var fake = configuration
        fake.executable = "/usr/bin/env"
        fake.extraArguments = ["python3", fixtureURL("fake_server.py").path, "basic"]
        fake.rawArgv = true
        fake.cwd = nil
        let client = RpcClient(configuration: fake)
        clients.append(client)
        return client
    })

    let first = try await manager.openNew(projectDirectory: "/tmp/project")
    do {
        _ = try await manager.openNew(projectDirectory: "/tmp/project")
        Issue.record("Expected duplicate session path to be rejected")
    } catch let error as SessionProcessManagerError {
        #expect(error == .duplicateSessionPath("/tmp/fake.jsonl"))
    }

    let spawned = clients.snapshot()
    #expect(spawned.count == 2)
    #expect(await manager.handle(for: first.sessionPath)?.client === first.client)
    #expect(await first.client.exitCode == nil)
    #expect(await spawned[1].exitCode != nil)
    await manager.closeAll()
}

@Test func joinedOpenSharesDuplicateActivationFailure() async throws {
    let gate = ActivationGate()
    let clients = ClientCapture()
    let manager = SessionProcessManager(
        clientFactory: { configuration in
            var fake = configuration
            fake.executable = "/usr/bin/env"
            fake.extraArguments = ["python3", fixtureURL("fake_server.py").path, "basic"]
            fake.rawArgv = true
            fake.cwd = nil
            let client = RpcClient(configuration: fake)
            clients.append(client)
            return client
        },
        beforeWarmActivation: {
            await gate.markEntered()
            await gate.waitUntilReleased()
        },
        beforeWarmRegistration: nil)

    _ = try await manager.warm(projectDirectory: "/tmp/project")
    let owner = Task { () throws -> SessionProcessManager.Handle in
        try await manager.open(sessionPath: "/tmp/fake.jsonl", cwd: "/tmp/project")
    }
    await gate.waitUntilEntered()
    let joined = Task { () throws -> SessionProcessManager.Handle in
        try await manager.open(sessionPath: "/tmp/fake.jsonl", cwd: "/tmp/project")
    }
    let claimant = try await manager.openNew(projectDirectory: "/tmp/project")
    await gate.release()

    do {
        _ = try await owner.value
        Issue.record("Expected owner to reject duplicate session path")
    } catch let error as SessionProcessManagerError {
        #expect(error == .duplicateSessionPath("/tmp/fake.jsonl"))
    }
    do {
        _ = try await joined.value
        Issue.record("Expected joined open to reject duplicate session path")
    } catch let error as SessionProcessManagerError {
        #expect(error == .duplicateSessionPath("/tmp/fake.jsonl"))
    }

    #expect(await manager.handle(for: claimant.sessionPath)?.client === claimant.client)
    let captured = clients.snapshot()
    #expect(captured.count == 2)
    #expect(await captured[0].exitCode != nil)
    #expect(await captured[1].exitCode == nil)
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

@Test func managerPreservesThousandGrowingMessageSnapshots() async throws {
    let manager = fakeManager(mode: "transcript-burst")
    let handle = try await manager.open(sessionPath: "/tmp/transcript-burst.jsonl", cwd: "/tmp")
    let stream = handle.client.events

    let acknowledgement = try await handle.client.send(
        .prompt(message: "burst", streamingBehavior: nil))
    #expect(acknowledgement.success)

    let result = await withTimeout(.seconds(10)) { () -> (
        eventTypes: [String], updates: [String], final: String?, terminalAgentEnds: Int,
        malformedUpdates: Int
    ) in
        var eventTypes: [String] = []
        var updates: [String] = []
        var final: String?
        var terminalAgentEnds = 0
        var malformedUpdates = 0

        for await frame in stream {
            guard case .event(let type, let payload) = frame else { continue }
            eventTypes.append(type)
            switch type {
            case "message_update":
                let message = payload["message"]
                let event = payload["assistantMessageEvent"]
                let usage = message?["usage"]
                let cost = usage?["cost"]
                let isContractComplete = event?["type"]?.stringValue == "text_delta"
                    && event?["contentIndex"]?.intValue == 0
                    && event?["delta"]?.stringValue == "x"
                    && event?["partial"] == message
                    && ["input", "output", "cacheRead", "cacheWrite", "totalTokens"]
                        .allSatisfy { usage?[$0]?.intValue == 0 }
                    && ["input", "output", "cacheRead", "cacheWrite", "total"]
                        .allSatisfy { cost?[$0]?.doubleValue == 0 }
                if !isContractComplete { malformedUpdates += 1 }
                updates.append(message?["content"]?.arrayValue?.first?["text"]?.stringValue ?? "")
            case "message_end":
                final = payload["message"]?["content"]?.arrayValue?.first?["text"]?.stringValue
            case "agent_end":
                guard payload["isTerminal"]?.boolValue == true else { continue }
                terminalAgentEnds += 1
                return (eventTypes, updates, final, terminalAgentEnds, malformedUpdates)
            default:
                break
            }
        }
        return (eventTypes, updates, final, terminalAgentEnds, malformedUpdates)
    }

    #expect(result != nil)
    let frames = result ?? (eventTypes: [], updates: [], final: nil, terminalAgentEnds: 0, malformedUpdates: 0)
    #expect(frames.eventTypes.first == "agent_start")
    #expect(frames.eventTypes.dropFirst().first == "message_start")
    #expect(frames.eventTypes.dropFirst(2).dropLast(2).allSatisfy { $0 == "message_update" })
    #expect(frames.eventTypes.suffix(2) == ["message_end", "agent_end"])
    #expect(frames.terminalAgentEnds == 1)
    #expect(frames.updates.count == 1_000)
    #expect(frames.malformedUpdates == 0)
    #expect(frames.updates.allSatisfy { !$0.isEmpty })
    #expect(zip(frames.updates, frames.updates.dropFirst()).allSatisfy { previous, current in
        current.count > previous.count && current.hasPrefix(previous)
    })
    #expect(frames.final == frames.updates.last)
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

@Test func eventBacklogOverflowIsReportedAsAnUnexpectedExitWithItsDiagnostic() async throws {
    let hooks: RpcClientTestHooks = {
        var hooks = RpcClientTestHooks()
        hooks.eventQueueLimits = BoundedRecordQueueLimits(
            memoryBytes: 8_192, memoryRecords: 4, spillBytes: 65_536)
        return hooks
    }()
    let manager = SessionProcessManager(clientFactory: { configuration in
        var fake = configuration
        fake.executable = "/usr/bin/env"
        fake.extraArguments = [
            "python3", fixtureURL("fake_server.py").path, "event-flood", "400", "4096",
        ]
        fake.rawArgv = true
        return RpcClient(configuration: fake, testHooks: hooks)
    })
    let handle = try await manager.open(sessionPath: "/tmp/flood.jsonl", cwd: "/tmp")
    let exits = manager.unexpectedExits

    // Nobody reads `events`; the flood overflows the small budget and the
    // client stops the session itself.
    _ = try? await handle.client.send(.getState(), timeout: .seconds(30))

    let exit = await withTimeout(.seconds(10)) { () -> SessionProcessManager.UnexpectedExit? in
        for await exit in exits { return exit }
        return nil
    } ?? nil
    #expect(exit?.sessionPath == "/tmp/flood.jsonl")
    #expect(exit?.stderrTail.hasPrefix("[OmpKit:RpcClient] The event backlog exceeded its") == true)
    #expect(await manager.handle(for: "/tmp/flood.jsonl") == nil)
    await manager.closeAll()
}

private final class ManagerBox: @unchecked Sendable {
    var manager: SessionProcessManager?
}

@Test func exitNoticedBeforeAReopenIsNotReportedAgainstTheReplacement() async throws {
    // "background-exit" exits one second after `set_subagent_subscription`,
    // which only the app sends, so the first child dies on request and the
    // second one stays alive.
    let box = ManagerBox()
    let manager = SessionProcessManager(
        clientFactory: { configuration in
            var fake = configuration
            fake.executable = "/usr/bin/env"
            fake.extraArguments = ["python3", fixtureURL("fake_server.py").path, "background-exit"]
            fake.rawArgv = true
            return RpcClient(configuration: fake)
        },
        beforeWarmActivation: nil,
        beforeWarmRegistration: nil,
        beforeExitReport: {
            _ = try? await box.manager?.open(sessionPath: "/tmp/reopened.jsonl", cwd: "/tmp")
        })
    box.manager = manager
    let first = try await manager.open(sessionPath: "/tmp/reopened.jsonl", cwd: "/tmp")
    let exits = manager.unexpectedExits
    _ = try await first.client.send(.setSubagentSubscription(level: .progress))

    let reported = await withTimeout(.seconds(6)) { () -> Bool in
        for await _ in exits { return true }
        return false
    }
    // nil: the wait timed out without a report, which is the required outcome.
    #expect(reported == nil)
    let replacement = await manager.handle(for: "/tmp/reopened.jsonl")
    #expect(replacement != nil)
    #expect(replacement?.client !== first.client)
    #expect(await replacement?.client.exitCode == nil)
    await manager.closeAll()
}
