import Foundation
import Testing
@testable import OmpKit

actor WarmSleepGate {
    private var sleepers: [Duration: [UUID: CheckedContinuation<Void, any Error>]] = [:]
    private var sleepingWaiters: [Duration: [CheckedContinuation<Void, Never>]] = [:]

    func sleep(for duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                sleepers[duration, default: [:]][id] = continuation
                let waiters = sleepingWaiters.removeValue(forKey: duration) ?? []
                for waiter in waiters { waiter.resume() }
            }
        } onCancel: {
            Task { await self.cancelSleep(id: id, for: duration) }
        }
    }

    func waitUntilSleeping(for duration: Duration) async {
        guard sleepers[duration]?.isEmpty != false else { return }
        await withCheckedContinuation { continuation in
            sleepingWaiters[duration, default: []].append(continuation)
        }
    }

    func release(_ duration: Duration) {
        let continuations = sleepers.removeValue(forKey: duration).map { Array($0.values) } ?? []
        for continuation in continuations { continuation.resume() }
    }

    private func cancelSleep(id: UUID, for duration: Duration) {
        let continuation = sleepers[duration]?.removeValue(forKey: id)
        if sleepers[duration]?.isEmpty == true { sleepers.removeValue(forKey: duration) }
        continuation?.resume(throwing: CancellationError())
    }
}

final class WarmManagerFixture: @unchecked Sendable {
    let root: URL
    let project: URL
    let commandLog: URL
    let manager: SessionProcessManager
    private let configurations = ConfigurationCapture()

    init(
        mode: String = "basic",
        warmGracePeriod: Duration = .seconds(300),
        sleep: @escaping SessionProcessManager.Sleep = { duration in
            try await ContinuousClock().sleep(for: duration)
        }
    ) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WarmManagerFixture-\(UUID().uuidString)", isDirectory: true)
        let project = root.appendingPathComponent("Project", isDirectory: true)
        let commandLog = root.appendingPathComponent("commands.log")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: commandLog.path, contents: nil)

        self.root = root
        self.project = project
        self.commandLog = commandLog
        self.manager = SessionProcessManager(
            warmGracePeriod: warmGracePeriod,
            sleep: sleep,
            clientFactory: { [configurations] configuration in
                configurations.append(configuration)
                var fake = configuration
                fake.executable = "/usr/bin/env"
                fake.extraArguments = ["python3", fixtureURL("fake_server.py").path, mode]
                    + (mode == "command-log" ? [commandLog.path] : [])
                fake.rawArgv = true
                fake.cwd = nil
                return RpcClient(configuration: fake)
            })
    }

    var configurationCount: Int { configurations.snapshot().count }

    func commands() throws -> [String] {
        try String(contentsOf: commandLog, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
    }

    func directory(_ name: String) throws -> URL {
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func waitUntil(_ condition: () async -> Bool) async {
        while !(await condition()) { await Task.yield() }
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

@Test func openNewChecksOutWarmClientAndCreatesARealSessionPath() async throws {
    let fixture = try WarmManagerFixture(mode: "command-log")
    defer { fixture.cleanup() }
    let manager = fixture.manager
    let warm = try await manager.warm(projectDirectory: fixture.project.path)

    let active = try await manager.openNew(projectDirectory: fixture.project.path)

    #expect(active.client === warm.client)
    #expect(active.sessionPath == "/tmp/fake.jsonl")
    #expect(fixture.configurationCount == 1)
    #expect(try fixture.commands() == [
        "negotiate_protocol", "new_session", "get_state",
    ])
    await manager.closeAll()
}

@Test func openExistingChecksOutWarmClientWithSwitchSession() async throws {
    let fixture = try WarmManagerFixture(mode: "command-log")
    defer { fixture.cleanup() }
    let manager = fixture.manager
    let warm = try await manager.warm(projectDirectory: fixture.project.path)

    let active = try await manager.open(
        sessionPath: "/tmp/existing.jsonl",
        cwd: fixture.project.path)

    #expect(active.client === warm.client)
    #expect(active.sessionPath == "/tmp/existing.jsonl")
    #expect(fixture.configurationCount == 1)
    #expect(try fixture.commands() == [
        "negotiate_protocol", "switch_session",
    ])
    await manager.closeAll()
}

@Test func secondConcurrentSessionInOneProjectSpawnsAColdChild() async throws {
    let fixture = try WarmManagerFixture(mode: "basic")
    defer { fixture.cleanup() }
    let manager = fixture.manager
    _ = try await manager.warm(projectDirectory: fixture.project.path)

    async let first = manager.open(sessionPath: "/tmp/one.jsonl", cwd: fixture.project.path)
    async let second = manager.open(sessionPath: "/tmp/two.jsonl", cwd: fixture.project.path)
    let handles = try await [first, second]

    #expect(handles[0].client !== handles[1].client)
    #expect(fixture.configurationCount == 2)
    await manager.closeAll()
}

@Test func concurrentOpenForOneSessionChecksOutOneWarmChild() async throws {
    let fixture = try WarmManagerFixture(mode: "basic")
    defer { fixture.cleanup() }
    let manager = fixture.manager
    _ = try await manager.warm(projectDirectory: fixture.project.path)

    async let first = manager.open(
        sessionPath: "/tmp/shared.jsonl", cwd: fixture.project.path)
    async let second = manager.open(
        sessionPath: "/tmp/shared.jsonl", cwd: fixture.project.path)
    let handles = try await [first, second]

    #expect(handles[0].client === handles[1].client)
    #expect(fixture.configurationCount == 1)
    await manager.closeAll()
}

@Test func gracePeriodEvictsOnlyTheUnclaimedSecondaryClient() async throws {
    let gate = WarmSleepGate()
    let fixture = try WarmManagerFixture(
        mode: "basic",
        warmGracePeriod: .seconds(300),
        sleep: { duration in try await gate.sleep(for: duration) })
    defer { fixture.cleanup() }
    let primary = try fixture.directory("Primary")
    let secondary = try fixture.directory("Secondary")
    let primaryHandle = try await fixture.manager.warm(projectDirectory: primary.path)
    let secondaryHandle = try await fixture.manager.warm(projectDirectory: secondary.path)

    await fixture.manager.beginWarmRetention(primaryProjectDirectory: primary.path)
    await gate.waitUntilSleeping(for: .seconds(300))
    await gate.release(.seconds(300))
    await fixture.waitUntil { await secondaryHandle.client.exitCode != nil }

    #expect(await fixture.manager.isWarm(projectDirectory: primary.path))
    #expect(await !fixture.manager.isWarm(projectDirectory: secondary.path))
    #expect(await primaryHandle.client.exitCode == nil)
    await fixture.manager.closeAll()
}

@Test func memoryPressureEvictsWarmClientsButNotCheckedOutClients() async throws {
    let fixture = try WarmManagerFixture(mode: "basic")
    defer { fixture.cleanup() }
    let warmOnly = try fixture.directory("WarmOnly")
    let activeProject = try fixture.directory("Active")
    _ = try await fixture.manager.warm(projectDirectory: warmOnly.path)
    _ = try await fixture.manager.warm(projectDirectory: activeProject.path)
    let active = try await fixture.manager.openNew(projectDirectory: activeProject.path)

    let evicted = await fixture.manager.evictWarmClients()

    #expect(evicted == [warmOnly.resolvingSymlinksInPath().path])
    #expect(await active.client.exitCode == nil)
    #expect(await fixture.manager.handle(for: active.sessionPath) != nil)
    await fixture.manager.closeAll()
}

@Test func failedNewSessionCheckoutReapsTheWarmChild() async throws {
    let fixture = try WarmManagerFixture(mode: "reject-new-session")
    defer { fixture.cleanup() }
    let warm = try await fixture.manager.warm(projectDirectory: fixture.project.path)

    await #expect(throws: RpcClientError.self) {
        _ = try await fixture.manager.openNew(projectDirectory: fixture.project.path)
    }

    #expect(await warm.client.exitCode != nil)
    #expect(await !fixture.manager.isWarm(projectDirectory: fixture.project.path))
    await fixture.manager.closeAll()
}

@Test func checkedOutSecondarySurvivesItsFormerGraceTimer() async throws {
    let gate = WarmSleepGate()
    let fixture = try WarmManagerFixture(
        mode: "basic",
        sleep: { duration in try await gate.sleep(for: duration) })
    defer { fixture.cleanup() }
    let primary = try fixture.directory("Primary")
    let secondary = try fixture.directory("Secondary")
    _ = try await fixture.manager.warm(projectDirectory: primary.path)
    _ = try await fixture.manager.warm(projectDirectory: secondary.path)
    await fixture.manager.beginWarmRetention(primaryProjectDirectory: primary.path)
    await gate.waitUntilSleeping(for: .seconds(300))
    let active = try await fixture.manager.openNew(projectDirectory: secondary.path)

    await gate.release(.seconds(300))
    #expect(await active.client.exitCode == nil)
    #expect(await fixture.manager.handle(for: active.sessionPath) != nil)
    await fixture.manager.closeAll()
}

@Test func checkedOutWarmCrashUsesTheActiveExitStream() async throws {
    let fixture = try WarmManagerFixture(mode: "crash-after-switch")
    defer { fixture.cleanup() }
    _ = try await fixture.manager.warm(projectDirectory: fixture.project.path)
    _ = try await fixture.manager.open(
        sessionPath: "/tmp/crashes.jsonl",
        cwd: fixture.project.path)

    let activeExit = await withTimeout(.seconds(5)) { () -> SessionProcessManager.UnexpectedExit? in
        for await exit in fixture.manager.unexpectedExits { return exit }
        return nil
    } ?? nil

    #expect(activeExit?.sessionPath == "/tmp/crashes.jsonl")
    #expect(activeExit?.code == 8)
    await fixture.manager.closeAll()
}

@Test func warmStartsOneNoSessionClientPerCanonicalProject() async throws {
    let capture = ConfigurationCapture()
    let manager = capturingManager(capture)
    let firstProject = URL(filePath: "/tmp/project-a").resolvingSymlinksInPath().path
    let secondProject = URL(filePath: "/tmp/project-b").resolvingSymlinksInPath().path

    async let first = manager.warm(projectDirectory: firstProject)
    async let second = manager.warm(projectDirectory: secondProject)
    let handles = try await [first, second]
    let configurations = capture.snapshot()
    let allNoSession = configurations.allSatisfy(\.noSession)

    #expect(handles.count == 2)
    #expect(configurations.count == 2)
    #expect(allNoSession)
    #expect(Set(configurations.compactMap { $0.cwd?.path }) == [
        firstProject, secondProject,
    ])
    await manager.closeAll()
}

@Test func concurrentWarmForOneProjectSharesOneChild() async throws {
    let capture = ConfigurationCapture()
    let manager = capturingManager(capture)
    async let first = manager.warm(projectDirectory: "/tmp/shared")
    async let second = manager.warm(projectDirectory: "/tmp/shared")
    let handles = try await [first, second]

    #expect(handles[0].client === handles[1].client)
    #expect(capture.snapshot().count == 1)
    await manager.closeAll()
}

@Test func warmExitIsReportedAndRemovedBeforeCheckout() async throws {
    let manager = capturingManager(ConfigurationCapture(), mode: "crash-after-negotiation")
    let project = URL(filePath: "/tmp/dies").resolvingSymlinksInPath().path
    _ = try await manager.warm(projectDirectory: project)
    let event = await withTimeout(.seconds(5)) { () -> SessionProcessManager.WarmExit? in
        for await exit in manager.unexpectedWarmExits { return exit }
        return nil
    } ?? nil

    #expect(event?.projectDirectory == project)
    #expect(event?.code == 7)
    #expect(await !manager.isWarm(projectDirectory: project))
    await manager.closeAll()
}

@Test func closeAllReapsWarmAndActiveClients() async throws {
    let manager = capturingManager(ConfigurationCapture())
    let warm = try await manager.warm(projectDirectory: "/tmp/warm")
    let active = try await manager.open(sessionPath: "/tmp/active.jsonl", cwd: "/tmp")

    await manager.closeAll()

    #expect(await warm.client.exitCode != nil)
    #expect(await active.client.exitCode != nil)
}

@Test func cancelWarmingsReapsAnInflightChildWithoutEvictingReadyWarmClients() async throws {
    let configurations = ConfigurationCapture()
    let clients = ClientCapture()
    let readyProject = URL(filePath: "/tmp/ready").resolvingSymlinksInPath().path
    let blockedProject = URL(filePath: "/tmp/blocked").resolvingSymlinksInPath().path
    let manager = SessionProcessManager(clientFactory: { configuration in
        configurations.append(configuration)
        var fake = configuration
        fake.executable = "/usr/bin/env"
        let mode = configuration.cwd?.path == readyProject ? "basic" : "never-ready"
        fake.extraArguments = ["python3", fixtureURL("fake_server.py").path, mode]
        fake.rawArgv = true
        fake.cwd = nil
        fake.startupTimeout = .seconds(30)
        let client = RpcClient(configuration: fake)
        clients.append(client)
        return client
    })
    _ = try await manager.warm(projectDirectory: readyProject)
    let blocked = Task {
        try? await manager.warm(projectDirectory: blockedProject)
    }
    while configurations.snapshot().count < 2 { await Task.yield() }

    let canceled = await manager.cancelWarmings()
    _ = await blocked.value

    #expect(canceled == [blockedProject])
    #expect(await manager.isWarm(projectDirectory: readyProject))
    #expect(await !manager.isWarm(projectDirectory: blockedProject))
    #expect(await clients.snapshot()[1].exitCode != nil)
    await manager.closeAll()
}

@Test func joinedWarmWaitersRejectALateResultAfterCancellation() async throws {
    let configurations = ConfigurationCapture()
    let clients = ClientCapture()
    let project = URL(filePath: "/tmp/joined-cancel").resolvingSymlinksInPath().path
    let manager = SessionProcessManager(clientFactory: { configuration in
        configurations.append(configuration)
        var fake = configuration
        fake.executable = "/usr/bin/env"
        fake.extraArguments = ["python3", fixtureURL("fake_server.py").path, "basic"]
        fake.rawArgv = true
        fake.cwd = nil
        let client = RpcClient(configuration: fake)
        clients.append(client)
        return client
    })
    let first = Task.detached(priority: .background) {
        do { return Result<SessionProcessManager.WarmHandle, any Error>.success(
            try await manager.warm(projectDirectory: project)) }
        catch { return .failure(error) }
    }
    while clients.snapshot().isEmpty { await Task.yield() }
    let second = Task.detached(priority: .background) {
        do { return Result<SessionProcessManager.WarmHandle, any Error>.success(
            try await manager.warm(projectDirectory: project)) }
        catch { return .failure(error) }
    }
    let canceller = Task.detached(priority: .high) {
        while await clients.snapshot()[0].negotiatedProtocolVersion != 2 { await Task.yield() }
        return await manager.cancelWarmings()
    }

    let canceled = await canceller.value
    let firstResult = await first.value
    let secondResult = await second.value
    let firstWasCanceled: Bool
    if case .failure(let error) = firstResult {
        firstWasCanceled = error is CancellationError
    } else {
        firstWasCanceled = false
    }
    let secondWasCanceled: Bool
    if case .failure(let error) = secondResult {
        secondWasCanceled = error is CancellationError
    } else {
        secondWasCanceled = false
    }

    #expect(canceled == [project])
    #expect(configurations.snapshot().count == 1)
    #expect(firstWasCanceled)
    #expect(secondWasCanceled)
    #expect(await clients.snapshot()[0].exitCode != nil)
    await manager.closeAll()
}
