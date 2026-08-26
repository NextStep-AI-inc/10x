import AppKit
import Foundation
import Testing
import XCTest
@testable import TenXApp

@MainActor
final class AppTerminationDelegateTests: XCTestCase {
    func testTerminationWithoutShutdownHandlerTerminatesImmediately() {
        let replies = TerminationReplyRecorder()
        let delegate = AppTerminationDelegate(reply: replies.reply)

        let first = delegate.applicationShouldTerminate(.shared)
        let second = delegate.applicationShouldTerminate(.shared)

        XCTAssertEqual(first, .terminateNow)
        XCTAssertEqual(second, .terminateNow)
        XCTAssertTrue(replies.values.isEmpty)
    }

    func testRepeatedTerminationRequestsShareOneShutdownAndOneSuccessReply() async {
        let shutdownGate = LoadGate()
        let counter = TerminationCounter()
        let replies = TerminationReplyRecorder()
        let delegate = AppTerminationDelegate(
            terminationGrace: .seconds(10),
            sleep: { _ in try await ContinuousClock().sleep(for: .seconds(60)) },
            reply: replies.reply)
        delegate.shutdown = {
            await counter.increment()
            await shutdownGate.started()
            await shutdownGate.waitForRelease()
        }

        XCTAssertEqual(delegate.applicationShouldTerminate(.shared), .terminateLater)
        await shutdownGate.waitForStart()
        XCTAssertEqual(delegate.applicationShouldTerminate(.shared), .terminateLater)
        var shutdownCount = await counter.currentValue()
        XCTAssertEqual(shutdownCount, 1)
        XCTAssertTrue(replies.values.isEmpty)

        await shutdownGate.release()
        await replies.waitForValues([true])

        shutdownCount = await counter.currentValue()
        XCTAssertEqual(shutdownCount, 1)
        XCTAssertEqual(replies.values, [true])
        XCTAssertEqual(delegate.applicationShouldTerminate(.shared), .terminateNow)
    }

    func testTerminationGraceRepliesWhenShutdownDoesNotReturn() async {
        let shutdownGate = LoadGate()
        let counter = TerminationCounter()
        let sleep = TerminationSleepRecorder()
        let replies = TerminationReplyRecorder()
        let delegate = AppTerminationDelegate(
            terminationGrace: .milliseconds(250),
            sleep: { duration in await sleep.sleep(duration) },
            reply: replies.reply)
        delegate.shutdown = {
            await counter.increment()
            await shutdownGate.started()
            await shutdownGate.waitForRelease()
        }

        XCTAssertEqual(delegate.applicationShouldTerminate(.shared), .terminateLater)
        await shutdownGate.waitForStart()
        await replies.waitForValues([true])
        XCTAssertEqual(delegate.applicationShouldTerminate(.shared), .terminateNow)

        await shutdownGate.release()
        await waitForModelState { await counter.currentValue() == 1 }
        let durations = await sleep.recordedDurations()
        XCTAssertEqual(durations, [.milliseconds(250)])
        XCTAssertEqual(replies.values, [true])
    }
}

@Test func startupAndWorkspaceUseDistinctStableSceneIDs() {
    #expect(AppWindowID.startup == "startup")
    #expect(AppWindowID.workspace == "workspace")
    #expect(AppWindowID.startup != AppWindowID.workspace)
}

@MainActor
@Test func shutdownCancelsBootstrapAndReapsWarmAndActiveChildren() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let manager = fixture.processManager()
    let model = fixture.model(processManager: manager)
    await model.bootstrap()
    let warm = try await manager.warm(projectDirectory: try fixture.project("Warm").path)
    let active = try await manager.open(
        sessionPath: "/tmp/active.jsonl",
        cwd: try fixture.project("Active").path)

    await model.shutdown()

    #expect(await warm.client.exitCode != nil)
    #expect(await active.client.exitCode != nil)
    #expect(await manager.handle(for: active.sessionPath) == nil)
}

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
@Test func continueCannotEnterWhileRuntimeReplacementOwnsLifecycleTeardown() async throws {
    let fixture = try StartupFixture()
    defer { fixture.cleanup() }
    let currentShutdownGate = LoadGate()
    let currentService = FakeProviderService(
        providers: [authenticatedProvider],
        shutdownGate: currentShutdownGate)
    let currentProvider = startupProviderModel(service: currentService)

    let replacementProviderGate = LoadGate()
    let replacementService = FakeProviderService(providers: [unauthenticatedProvider])
    await replacementService.enqueueProviderGate(replacementProviderGate)
    let replacementUsage = FakeUsageService(snapshot: try usageSnapshotFixture())
    let replacementProvider = startupProviderModel(
        service: replacementService,
        usageService: replacementUsage)

    let unexpectedService = FakeProviderService(providers: [authenticatedProvider])
    let unexpectedUsage = FakeUsageService(snapshot: .empty)
    let unexpectedProvider = startupProviderModel(
        service: unexpectedService,
        usageService: unexpectedUsage)
    let providerFactory = StartupProviderModelFactory(
        models: [currentProvider, replacementProvider, unexpectedProvider])
    let locator = CountingOmpLocator(installation: fixture.installation)
    let model = fixture.model(locator: locator, providerFactory: providerFactory)
    await model.useOmp(at: URL(filePath: "/tmp/current-omp"))
    enterRuntimeRecovery(model, installation: fixture.installation)

    let firstContinue = Task { await model.continueToWorkspace() }
    await waitForModelState { await currentService.shutdownCount == 1 }
    let generationBeforeReplacement = model.lifecycleGeneration
    let replacement = Task {
        await model.useOmp(at: URL(filePath: "/tmp/replacement-omp"))
    }
    await waitForModelState {
        await Task.yield()
        return model.lifecycleGeneration > generationBeforeReplacement
    }

    await model.continueToWorkspace()
    if model.fallbackGeneration > 0 {
        await waitForModelState { await replacementService.providerLoadCount == 1 }
    }
    #expect(model.fallbackGeneration == 0)
    #expect(providerFactory.count == 1)
    #expect(await replacementService.providerLoadCount == 0)
    #expect(await replacementUsage.loadCount == 0)

    await currentShutdownGate.release()
    await waitForModelState { await replacementService.providerLoadCount == 1 }
    await replacementProviderGate.release()
    await firstContinue.value
    await replacement.value
    if model.providerModel === replacementProvider {
        await waitForModelState { model.providerUsages.map(\.id) == ["cursor"] }
    }

    #expect(model.providerModel === replacementProvider)
    #expect(model.route == .providerSetup)
    #expect(model.providerUsages.map(\.id) == ["cursor"])
    #expect(providerFactory.count == 2)
    #expect(await currentService.shutdownCount == 1)
    #expect(await replacementService.providerLoadCount == 1)
    #expect(await replacementUsage.loadCount == 1)
    #expect(await replacementService.shutdownCount == 0)
    #expect(await unexpectedService.providerLoadCount == 0)
    #expect(await unexpectedUsage.loadCount == 0)

    await model.shutdown()
    #expect(await replacementService.shutdownCount == 1)
    #expect(await unexpectedService.shutdownCount == 0)
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
private final class TerminationReplyRecorder {
    private(set) var values: [Bool] = []
    private var waiters: [([Bool], CheckedContinuation<Void, Never>)] = []

    func reply(_: NSApplication, _ shouldTerminate: Bool) {
        values.append(shouldTerminate)
        let readyWaiters = waiters.filter { values == $0.0 }
        waiters.removeAll { values == $0.0 }
        for waiter in readyWaiters {
            waiter.1.resume()
        }
    }

    func waitForValues(_ expected: [Bool]) async {
        guard values != expected else { return }
        await withCheckedContinuation { waiters.append((expected, $0)) }
    }
}

private actor TerminationCounter {
    private var value = 0

    func increment() {
        value += 1
    }

    func currentValue() -> Int {
        value
    }
}

private actor TerminationSleepRecorder {
    private var durations: [Duration] = []

    func sleep(_ duration: Duration) {
        durations.append(duration)
    }

    func recordedDurations() -> [Duration] {
        durations
    }
}

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
