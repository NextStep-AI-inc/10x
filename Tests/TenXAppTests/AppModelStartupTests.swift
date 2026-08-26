import Foundation
import Testing
@testable import TenXApp

@MainActor
@Test func concurrentBootstrapCallsShareOneAttemptAndRespectTheFloor() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let locator = CountingOmpLocator(installation: fixture.installation)
    let minimumGate = LoadGate()
    let timing = StartupTiming(
        minimumVisibility: .milliseconds(350),
        timeout: .seconds(10),
        sleep: { duration in
            if duration == .milliseconds(350) {
                await minimumGate.started()
                await minimumGate.waitForRelease()
            } else {
                try await ContinuousClock().sleep(for: .seconds(60))
            }
        })
    let model = fixture.model(locator: locator, timing: timing)

    async let first: Void = model.bootstrap()
    async let second: Void = model.bootstrap()
    await minimumGate.waitForStart()

    let locateCount = await locator.count
    #expect(locateCount == 1)
    #expect(model.startupState.handoffGeneration == 0)
    await minimumGate.release()
    await first
    await second
    #expect(model.startupState.handoffGeneration == 1)
    await model.shutdown()
}

@MainActor
@Test func missingOmpHandsOffToSetupWithoutWaitingForTheWatchdog() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let timeoutGate = LoadGate()
    let timing = StartupTiming(
        minimumVisibility: .zero,
        timeout: .seconds(10),
        sleep: { duration in
            if duration == .seconds(10) {
                await timeoutGate.started()
                try await ContinuousClock().sleep(for: .seconds(60))
            }
        })
    let model = fixture.model(
        locator: CountingOmpLocator(installation: nil),
        timing: timing)

    await model.bootstrap()

    #expect(model.route == .setup)
    #expect(model.startupState.handoffGeneration == 1)
    #expect(model.startupState.phase == .handoff)
    await model.shutdown()
}

@MainActor
@Test func bootstrapWarmsTwoRecentProjectsBeforeHandoff() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let older = try fixture.project("Older")
    let newer = try fixture.project("Newer")
    try fixture.writeSession(cwd: older, modified: Date(timeIntervalSince1970: 10))
    try fixture.writeSession(cwd: newer, modified: Date(timeIntervalSince1970: 20))
    let manager = fixture.processManager()
    let model = fixture.model(processManager: manager)

    await model.bootstrap()

    #expect(model.startupState.phase == .handoff)
    #expect(await manager.isWarm(projectDirectory: newer.path))
    #expect(await manager.isWarm(projectDirectory: older.path))
    #expect(model.selectedProjectURL == newer.resolvingSymlinksInPath())
    #expect(model.sessions.count == 2)
    await model.shutdown()
}

@MainActor
@Test func watchdogStopsUnfinishedRowsAndRetryKeepsReadyRows() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let settingsGate = LoadGate()
    let timeoutGate = LoadGate()
    let settingsRunner = StartupConfigRunner(
        startedGate: settingsGate,
        isBlocked: true)
    let model = fixture.model(
        timing: .controlledTimeout(timeoutGate),
        settingsRunner: settingsRunner)
    let bootstrap = Task { await model.bootstrap() }
    await settingsGate.waitForStart()
    await waitForModelState {
        model.startupState.status(of: .runtime) == .ready
    }
    await timeoutGate.release()
    await bootstrap.value

    #expect(model.startupState.phase == .recovery)
    #expect(model.startupState.status(of: .runtime) == .ready)
    #expect(model.startupState.status(of: .settings) == .stopped)
    await settingsRunner.setBlocked(false)
    await model.bootstrap()
    #expect(model.startupState.phase == .recovery)
    await model.retryStartup()
    #expect(model.startupState.phase == .handoff)
    #expect(model.startupState.status(of: .runtime) == .ready)
    await model.shutdown()
}

@MainActor
@Test func continueKeepsSuccessfulWarmClientAndStartsWorkspaceFallbackLoads() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let first = try fixture.project("First")
    let second = try fixture.project("Second")
    let manager = fixture.mixedWarmManager(
        readyProject: first,
        stalledProject: second)
    let timeoutGate = LoadGate()
    let model = fixture.model(
        processManager: manager,
        timing: .controlledTimeout(timeoutGate))
    model.chooseProject(first)
    try fixture.writeSession(cwd: second, modified: .now)

    let bootstrap = Task { await model.bootstrap() }
    await waitForModelState { await manager.isWarm(projectDirectory: first.path) }
    await waitForModelState { fixture.mixedWarmConfigurationCount == 2 }
    let stalledClient = try #require(fixture.mixedWarmClient(for: second))
    await timeoutGate.release()
    await bootstrap.value
    #expect(model.startupState.phase == .recovery)
    await model.continueToWorkspace()

    #expect(model.startupState.phase == .handoff)
    #expect(await manager.isWarm(projectDirectory: first.path))
    #expect(await !manager.isWarm(projectDirectory: second.path))
    #expect(await stalledClient.exitCode != nil)
    await model.shutdown()
}

@MainActor
@Test func memoryPressureBeforeHandoffEvictsWarmClientsAndMakesTheStageRetryable() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let project = try fixture.project("Pressure")
    let minimumGate = LoadGate()
    let timing = StartupTiming(
        minimumVisibility: .milliseconds(350),
        timeout: .seconds(10),
        sleep: { duration in
            if duration == .milliseconds(350) { await minimumGate.started() }
            try await ContinuousClock().sleep(for: .seconds(60))
        })
    let manager = fixture.processManager()
    let model = fixture.model(processManager: manager, timing: timing)
    model.chooseProject(project)
    let bootstrap = Task { await model.bootstrap() }
    await waitForModelState { await manager.isWarm(projectDirectory: project.path) }

    await model.handleMemoryPressure()
    await bootstrap.value

    #expect(model.startupState.phase == .recovery)
    #expect(model.startupState.status(of: .recentProjects) == .stopped)
    #expect(await !manager.isWarm(projectDirectory: project.path))
    await model.shutdown()
}

@MainActor
@Test func warmCrashBeforeHandoffPreservesAnotherReadyWarmClient() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let stable = try fixture.project("Stable")
    let crashing = try fixture.project("Crashing")
    let trigger = fixture.file("pre-handoff-crash.trigger")
    let minimumGate = LoadGate()
    let (floorRelease, floorReleaseContinuation) = AsyncStream<Void>.makeStream(
        bufferingPolicy: .bufferingNewest(1))
    defer { floorReleaseContinuation.finish() }
    let timing = StartupTiming(
        minimumVisibility: .milliseconds(350),
        timeout: .seconds(10),
        sleep: { duration in
            if duration == .milliseconds(350) {
                await minimumGate.started()
                for await _ in floorRelease { break }
                try Task.checkCancellation()
            } else {
                try await ContinuousClock().sleep(for: .seconds(60))
            }
        })
    let manager = fixture.triggeredCrashManager(
        project: crashing,
        trigger: trigger)
    _ = try await manager.warm(projectDirectory: stable.path)
    let model = fixture.model(processManager: manager, timing: timing)
    model.chooseProject(stable)
    try fixture.writeSession(cwd: crashing, modified: .now)

    let bootstrap = Task { await model.bootstrap() }
    await minimumGate.waitForStart()
    await waitForModelState {
        let stableIsWarm = await manager.isWarm(projectDirectory: stable.path)
        let crashingIsWarm = await manager.isWarm(projectDirectory: crashing.path)
        return stableIsWarm && crashingIsWarm
    }
    #expect(model.startupState.phase == .preparing)
    #expect(model.startupState.handoffGeneration == 0)

    try Data().write(to: trigger)
    await waitForModelState {
        await !manager.isWarm(projectDirectory: crashing.path)
    }
    await waitForModelState {
        model.startupState.phase == .recovery
            && model.startupState.status(of: .recentProjects) == .stopped
    }

    #expect(model.startupState.phase == .recovery)
    #expect(model.startupState.status(of: .recentProjects) == .stopped)
    #expect(await manager.isWarm(projectDirectory: stable.path))
    floorReleaseContinuation.yield()
    floorReleaseContinuation.finish()
    await bootstrap.value
    await model.shutdown()
}

@MainActor
@Test func warmExitAfterHandoffDoesNotReplayStartupRecovery() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let project = try fixture.project("PostHandoff")
    let trigger = fixture.file("post-handoff-crash.trigger")
    let manager = fixture.triggeredCrashManager(
        project: project,
        trigger: trigger)
    let model = fixture.model(processManager: manager)
    model.chooseProject(project)
    await model.bootstrap()
    #expect(model.startupState.phase == .handoff)

    try Data().write(to: trigger)
    await waitForModelState { await !manager.isWarm(projectDirectory: project.path) }
    for _ in 0..<20 { await Task.yield() }

    #expect(model.startupState.phase == .handoff)
    #expect(model.startupState.handoffGeneration == 1)
    await model.shutdown()
}

@MainActor
@Test func sessionWatcherRefreshesMetadataAfterHandoff() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let model = fixture.model()
    await model.bootstrap()
    #expect(model.sessions.isEmpty)

    try fixture.writeSession(cwd: try fixture.project("Watched"), modified: .now)
    await waitForModelState { model.sessions.count == 1 }

    #expect(model.sessions.first?.cwd.hasSuffix("Watched") == true)
    await model.shutdown()
}
