import Foundation
import Synchronization
import Testing
@testable import OmpKit

actor WarmSleepGate {
    private struct SleepingWaiter {
        let count: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private var sleepers: [Duration: [UUID: CheckedContinuation<Void, any Error>]] = [:]
    private var sleepingWaiters: [Duration: [SleepingWaiter]] = [:]
    private var cancellationCounts: [Duration: Int] = [:]
    private var cancellationWaiters: [Duration: [UUID: CheckedContinuation<Void, Never>]] = [:]

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
                let sleeperCount = sleepers[duration, default: [:]].count
                let waiters = sleepingWaiters[duration, default: []]
                sleepingWaiters[duration] = waiters.filter { waiter in
                    guard waiter.count <= sleeperCount else { return true }
                    waiter.continuation.resume()
                    return false
                }
            }
        } onCancel: {
            Task { await self.cancelSleep(id: id, for: duration) }
        }
    }

    func waitUntilSleeping(for duration: Duration, count: Int = 1) async {
        guard sleepers[duration, default: [:]].count < count else { return }
        await withCheckedContinuation { continuation in
            sleepingWaiters[duration, default: []].append(
                SleepingWaiter(count: count, continuation: continuation))
        }
    }

    func release(_ duration: Duration) {
        let continuations = sleepers.removeValue(forKey: duration).map { Array($0.values) } ?? []
        for continuation in continuations { continuation.resume() }
    }

    func waitUntilCancelled(for duration: Duration) async {
        guard cancellationCounts[duration, default: 0] == 0 else { return }
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                cancellationWaiters[duration, default: [:]][id] = continuation
            }
        } onCancel: {
            Task { await self.cancelCancellationWait(id: id, for: duration) }
        }
    }

    private func cancelSleep(id: UUID, for duration: Duration) {
        let continuation = sleepers[duration]?.removeValue(forKey: id)
        if sleepers[duration]?.isEmpty == true { sleepers.removeValue(forKey: duration) }
        cancellationCounts[duration, default: 0] += 1
        let waiters = cancellationWaiters.removeValue(forKey: duration).map { Array($0.values) } ?? []
        for waiter in waiters { waiter.resume() }
        continuation?.resume(throwing: CancellationError())
    }

    private func cancelCancellationWait(id: UUID, for duration: Duration) {
        cancellationWaiters[duration]?.removeValue(forKey: id)
        if cancellationWaiters[duration]?.isEmpty == true {
            cancellationWaiters.removeValue(forKey: duration)
        }
    }
}

final class ConfigurationRecorder: Sendable {
    private let values = Mutex<[RpcClientConfiguration]>([])

    func append(_ configuration: RpcClientConfiguration) {
        values.withLock { $0.append(configuration) }
    }

    func count() -> Int {
        values.withLock { $0.count }
    }
}

final class WarmManagerFixture {
    let root: URL
    let project: URL
    let commandLog: URL
    let manager: SessionProcessManager
    private let configurations = ConfigurationRecorder()
    let clients: ClientCapture

    init(
        mode: String = "basic",
        modeArguments: [String] = [],
        warmGracePeriod: Duration = .seconds(300),
        beforeWarmActivation: (@Sendable () async -> Void)? = nil,
        beforeWarmRegistration: (@Sendable () async -> Void)? = nil,
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
        let clients = ClientCapture()
        self.clients = clients
        self.manager = SessionProcessManager(
            warmGracePeriod: warmGracePeriod,
            sleep: sleep,
            clientFactory: { [configurations, clients] configuration in
                configurations.append(configuration)
                var fake = configuration
                fake.executable = "/usr/bin/env"
                fake.extraArguments = ["python3", fixtureURL("fake_server.py").path, mode]
                    + modeArguments
                    + (mode == "command-log" ? [commandLog.path] : [])
                fake.rawArgv = true
                fake.cwd = nil
                let client = RpcClient(configuration: fake)
                clients.append(client)
                return client
            },
            beforeWarmActivation: beforeWarmActivation,
            beforeWarmRegistration: beforeWarmRegistration)
    }

    var configurationCount: Int { configurations.count() }

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

@Test func closeAllCancelsWarmInFlightNewSessionCheckout() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("WarmCheckoutTrigger-\(UUID().uuidString)", isDirectory: true)
    let entered = root.appendingPathComponent("entered")
    let release = root.appendingPathComponent("release")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let fixture = try WarmManagerFixture(
        mode: "block-new-session",
        modeArguments: [release.path, entered.path])
    defer {
        fixture.cleanup()
        try? FileManager.default.removeItem(at: root)
    }
    let manager = fixture.manager
    let projectPath = fixture.project.path
    _ = try await manager.warm(projectDirectory: projectPath)
    let checkout = Task { try? await manager.openNew(projectDirectory: projectPath) }
    await fixture.waitUntil { FileManager.default.fileExists(atPath: entered.path) }

    await manager.closeAll()
    FileManager.default.createFile(atPath: release.path, contents: nil)
    let handle = await checkout.value

    #expect(handle == nil)
    #expect(await manager.handle(for: "/tmp/fake.jsonl") == nil)
    await manager.closeAll()
}

@Test func closeAllCancelsColdInFlightNewSessionCheckout() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ColdCheckoutTrigger-\(UUID().uuidString)", isDirectory: true)
    let entered = root.appendingPathComponent("entered")
    let release = root.appendingPathComponent("release")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let fixture = try WarmManagerFixture(
        mode: "block-get-state",
        modeArguments: [release.path, entered.path])
    defer {
        fixture.cleanup()
        try? FileManager.default.removeItem(at: root)
    }
    let manager = fixture.manager
    let projectPath = fixture.project.path
    let checkout = Task { try? await manager.openNew(projectDirectory: projectPath) }
    await fixture.waitUntil { FileManager.default.fileExists(atPath: entered.path) }

    await manager.closeAll()
    FileManager.default.createFile(atPath: release.path, contents: nil)
    let handle = await checkout.value

    #expect(handle == nil)
    #expect(await manager.handle(for: "/tmp/fake.jsonl") == nil)
    await manager.closeAll()
}

@Test func laterPrimaryRetentionCancelsExistingExpiry() async throws {
    let gate = WarmSleepGate()
    let fixture = try WarmManagerFixture(
        mode: "basic",
        sleep: { duration in try await gate.sleep(for: duration) })
    defer { fixture.cleanup() }
    let first = try fixture.directory("First")
    let second = try fixture.directory("Second")
    let firstHandle = try await fixture.manager.warm(projectDirectory: first.path)
    _ = try await fixture.manager.warm(projectDirectory: second.path)

    await fixture.manager.beginWarmRetention(primaryProjectDirectory: second.path)
    await gate.waitUntilSleeping(for: .seconds(300))
    await fixture.manager.beginWarmRetention(primaryProjectDirectory: first.path)
    let canceledFormerExpiry = await withTimeout(.seconds(1)) {
        await gate.waitUntilCancelled(for: .seconds(300))
        return true
    } ?? false
    #expect(canceledFormerExpiry)
    await gate.release(.seconds(300))

    #expect(await fixture.manager.isWarm(projectDirectory: first.path))
    #expect(await firstHandle.client.exitCode == nil)
    await fixture.manager.closeAll()
}

@Test func warmTransitionCrashReportsActiveExitWithoutRegisteringDeadHandle() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("WarmTransitionCrash-\(UUID().uuidString)", isDirectory: true)
    let release = root.appendingPathComponent("release")
    let gate = WarmSleepGate()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let fixture = try WarmManagerFixture(
        mode: "crash-after-switch-trigger",
        modeArguments: [release.path],
        beforeWarmActivation: { try? await gate.sleep(for: .zero) })
    defer {
        fixture.cleanup()
        try? FileManager.default.removeItem(at: root)
    }
    let manager = fixture.manager
    let projectPath = fixture.project.path
    let sessionPath = "/tmp/transition-crash.jsonl"
    let exitStream = manager.unexpectedExits
    _ = try await manager.warm(projectDirectory: projectPath)
    let checkout = Task { try? await manager.open(sessionPath: sessionPath, cwd: projectPath) }
    await gate.waitUntilSleeping(for: .zero)

    FileManager.default.createFile(atPath: release.path, contents: nil)
    let exit = await withTimeout(.seconds(5)) { () -> SessionProcessManager.UnexpectedExit? in
        for await event in exitStream { return event }
        return nil
    } ?? nil
    await gate.release(.zero)
    let handle = await checkout.value

    #expect(exit?.sessionPath == sessionPath)
    #expect(exit?.code == 10)
    #expect(handle == nil)
    #expect(await manager.handle(for: sessionPath) == nil)
    await manager.closeAll()
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

@Test func openNewAppliesComposerSelectionToWarmClient() async throws {
    let fixture = try WarmManagerFixture(mode: "command-log")
    defer { fixture.cleanup() }
    let manager = fixture.manager
    let warm = try await manager.warm(projectDirectory: fixture.project.path)

    let active = try await manager.openNew(
        projectDirectory: fixture.project.path,
        provider: "anthropic",
        model: "claude-opus-4-8",
        thinking: "high")

    #expect(active.client === warm.client)
    #expect(try fixture.commands() == [
        "negotiate_protocol",
        "new_session",
        "set_model",
        "set_thinking_level",
        "get_state",
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
    let projectPath = fixture.project.path
    _ = try await manager.warm(projectDirectory: projectPath)

    async let first = manager.open(sessionPath: "/tmp/one.jsonl", cwd: projectPath)
    async let second = manager.open(sessionPath: "/tmp/two.jsonl", cwd: projectPath)
    let handles = try await [first, second]

    #expect(handles[0].client !== handles[1].client)
    #expect(fixture.configurationCount == 2)
    await manager.closeAll()
}

@Test func concurrentOpenForOneSessionChecksOutOneWarmChild() async throws {
    let fixture = try WarmManagerFixture(mode: "basic")
    defer { fixture.cleanup() }
    let manager = fixture.manager
    let projectPath = fixture.project.path
    _ = try await manager.warm(projectDirectory: projectPath)

    async let first = manager.open(
        sessionPath: "/tmp/shared.jsonl", cwd: projectPath)
    async let second = manager.open(
        sessionPath: "/tmp/shared.jsonl", cwd: projectPath)
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
    let manager = fixture.manager
    _ = try await manager.warm(projectDirectory: fixture.project.path)
    _ = try await manager.open(
        sessionPath: "/tmp/crashes.jsonl",
        cwd: fixture.project.path)

    let activeExit = await withTimeout(.seconds(5)) { () -> SessionProcessManager.UnexpectedExit? in
        for await exit in manager.unexpectedExits { return exit }
        return nil
    } ?? nil

    #expect(activeExit?.sessionPath == "/tmp/crashes.jsonl")
    #expect(activeExit?.code == 8)
    await manager.closeAll()
}

@Test func warmStartsOneFreshPersistentClientPerCanonicalProject() async throws {
    let capture = ConfigurationCapture()
    let manager = capturingManager(capture)
    let firstProject = URL(filePath: "/tmp/project-a").resolvingSymlinksInPath().path
    let secondProject = URL(filePath: "/tmp/project-b").resolvingSymlinksInPath().path

    async let first = manager.warm(projectDirectory: firstProject)
    async let second = manager.warm(projectDirectory: secondProject)
    let handles = try await [first, second]
    let configurations = capture.snapshot()

    #expect(handles.count == 2)
    #expect(configurations.count == 2)
    #expect(configurations.allSatisfy { configuration in
        guard let cwd = configuration.cwd?.path else { return false }
        return configuration.noSession == false
            && configuration.extraArguments == [
                "--session-dir", expectedFreshSessionDirectory(for: cwd),
            ]
    })
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
    let gate = WarmSleepGate()
    let fixture = try WarmManagerFixture(
        mode: "basic",
        beforeWarmRegistration: { try? await gate.sleep(for: .zero) })
    defer { fixture.cleanup() }
    let manager = fixture.manager
    let project = fixture.project.path
    let first = Task {
        do { return Result<SessionProcessManager.WarmHandle, any Error>.success(
            try await manager.warm(projectDirectory: project)) }
        catch { return .failure(error) }
    }
    let second = Task {
        do { return Result<SessionProcessManager.WarmHandle, any Error>.success(
            try await manager.warm(projectDirectory: project)) }
        catch { return .failure(error) }
    }

    await gate.waitUntilSleeping(for: .zero, count: 2)
    let canceled = await manager.cancelWarmings()
    await gate.release(.zero)
    let firstResult = await first.value
    let secondResult = await second.value

    #expect(canceled == [project])
    #expect(fixture.configurationCount == 1)
    #expect(fixture.clients.snapshot().count == 1)
    #expect(throws: CancellationError.self) { try firstResult.get() }
    #expect(throws: CancellationError.self) { try secondResult.get() }
    #expect(await fixture.clients.snapshot()[0].exitCode != nil)
    await manager.closeAll()
}
