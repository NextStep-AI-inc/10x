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

@MainActor
@Test func concurrentContinueCallsStartOnlyOneFallbackGeneration() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let providerGate = LoadGate()
    let providerService = FakeProviderService(providers: [authenticatedProvider])
    await providerService.enqueueProviderGate(providerGate)
    let provider = startupProviderModel(service: providerService)
    let providerFactory = StartupProviderModelFactory(models: [provider])
    let model = fixture.model(providerFactory: providerFactory)
    enterRuntimeRecovery(model, installation: fixture.installation)

    async let first: Void = model.continueToWorkspace()
    async let second: Void = model.continueToWorkspace()
    await providerGate.waitForStart()
    await first
    await second

    #expect(model.startupState.handoffGeneration == 1)
    #expect(model.fallbackGeneration == 1)
    #expect(providerFactory.count == 1)
    #expect(await providerService.providerLoadCount == 1)
    await providerGate.release()
    await model.shutdown()
}

@MainActor
@Test func shutdownDuringBlockedFallbackReapsBeforeStateCanMutate() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let startupProviderGate = LoadGate()
    let timeoutGate = LoadGate()
    let startupProviderService = FakeProviderService(providers: [authenticatedProvider])
    await startupProviderService.enqueueProviderGate(startupProviderGate)
    let startupProvider = startupProviderModel(service: startupProviderService)

    let fallbackProviderGate = LoadGate()
    let usageGate = LoadGate()
    let fallbackProviderService = FakeProviderService(providers: [authenticatedProvider])
    let usageService = FakeUsageService(snapshot: try usageSnapshotFixture())
    await fallbackProviderService.enqueueProviderGate(fallbackProviderGate)
    await usageService.enqueueLoadGate(usageGate)
    let fallbackProvider = startupProviderModel(
        service: fallbackProviderService,
        usageService: usageService)
    let providerFactory = StartupProviderModelFactory(
        models: [startupProvider, fallbackProvider])
    let model = fixture.model(
        timing: .controlledTimeout(timeoutGate),
        providerFactory: providerFactory)
    let bootstrap = Task { await model.bootstrap() }
    await startupProviderGate.waitForStart()
    await timeoutGate.waitForStart()
    await timeoutGate.release()
    await waitForModelState {
        await startupProviderService.shutdownCount == 1
    }
    await startupProviderGate.release()
    await bootstrap.value
    #expect(model.startupState.phase == .recovery)

    let manager = try #require(model.processManager)
    let warmProject = try fixture.project("ShutdownWarm")
    let warm = try await manager.warm(projectDirectory: warmProject.path)
    await model.continueToWorkspace()
    await fallbackProviderGate.waitForStart()
    await usageGate.waitForStart()
    let routeBeforeShutdown = model.route

    let shutdown = Task { await model.shutdown() }
    await waitForModelState {
        await Task.yield()
        return model.isShuttingDown
    }
    #expect(await fallbackProviderService.shutdownCount == 0)
    await fallbackProviderGate.release()
    await usageGate.release()
    await shutdown.value
    for _ in 0..<20 { await Task.yield() }

    #expect(model.route == routeBeforeShutdown)
    #expect(model.providerUsages.isEmpty)
    #expect(providerFactory.count == 2)
    #expect(await startupProviderService.shutdownCount == 1)
    #expect(await fallbackProviderService.shutdownCount == 1)
    #expect(await usageService.loadCount == 1)
    #expect(await warm.client.exitCode != nil)
    #expect(await !manager.isWarm(projectDirectory: warmProject.path))
}

@MainActor
@Test func replacementWaitsForBlockedFallbackBeforeCapturingRuntimeOwners() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let providerGate = LoadGate()
    let fallbackService = FakeProviderService(providers: [authenticatedProvider])
    await fallbackService.enqueueProviderGate(providerGate)
    let fallbackProvider = startupProviderModel(service: fallbackService)
    let replacementService = FakeProviderService(providers: [unauthenticatedProvider])
    let replacementProvider = startupProviderModel(service: replacementService)
    let providerFactory = StartupProviderModelFactory(
        models: [fallbackProvider, replacementProvider])
    let locator = CountingOmpLocator(installation: fixture.installation)
    let model = fixture.model(locator: locator, providerFactory: providerFactory)
    enterRuntimeRecovery(model, installation: fixture.installation)
    await model.continueToWorkspace()
    await providerGate.waitForStart()

    let lifecycleGeneration = model.lifecycleGeneration
    let replacement = Task {
        await model.useOmp(at: URL(filePath: "/tmp/replacement-omp"))
    }
    await waitForModelState {
        await Task.yield()
        return model.lifecycleGeneration > lifecycleGeneration
    }
    #expect(await fallbackService.shutdownCount == 0)
    await providerGate.release()
    await replacement.value

    #expect(model.providerModel === replacementProvider)
    #expect(model.route == .providerSetup)
    #expect(providerFactory.count == 2)
    #expect(await fallbackService.shutdownCount == 1)
    await model.shutdown()
    #expect(await replacementService.shutdownCount == 1)
}

@MainActor
@Test func workspaceDidOpenRetainsPrimaryAndExpiresOnlySecondaryWarmClient() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let gate = StartupRetentionGate()
    let manager = fixture.retentionManager(gate: gate)
    let primary = try fixture.project("RetentionPrimary")
    let secondary = try fixture.project("RetentionSecondary")
    let primaryHandle = try await manager.warm(projectDirectory: primary.path)
    let secondaryHandle = try await manager.warm(projectDirectory: secondary.path)
    let model = fixture.model(processManager: manager)
    model.chooseProject(primary)
    await model.bootstrap()
    #expect(await manager.isWarm(projectDirectory: primary.path))
    #expect(await manager.isWarm(projectDirectory: secondary.path))

    await model.workspaceDidOpen()
    await gate.waitForStart()
    await model.workspaceDidOpen()
    await gate.release()
    await waitForModelState { await secondaryHandle.client.exitCode != nil }

    #expect(await manager.isWarm(projectDirectory: primary.path))
    #expect(await !manager.isWarm(projectDirectory: secondary.path))
    #expect(await primaryHandle.client.exitCode == nil)
    await model.shutdown()
}

private let authenticatedProvider = ProviderLoginProvider(
    id: "cursor",
    name: "Cursor",
    isAvailable: true,
    isAuthenticated: true)

private let unauthenticatedProvider = ProviderLoginProvider(
    id: "cursor",
    name: "Cursor",
    isAvailable: true,
    isAuthenticated: false)

@MainActor
private func startupProviderModel(
    service: FakeProviderService,
    usageService: FakeUsageService = FakeUsageService(snapshot: .empty)
) -> ProviderManagementViewModel {
    ProviderManagementViewModel(
        providerService: service,
        usageService: usageService,
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })
}

@MainActor
private func enterRuntimeRecovery(
    _ model: AppModel,
    installation: OmpInstallation
) {
    let attemptID = UUID()
    model.installation = installation
    model.startupState.beginAttempt(id: attemptID)
    for stage in StartupStageID.allCases where stage != .runtime {
        model.startupState.markReady(stage, attemptID: attemptID)
    }
    model.startupState.enterRecovery(attemptID: attemptID)
}
