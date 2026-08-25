import Foundation
import OmpKit
import Testing
@testable import TenXApp

@MainActor
@Test func openSettingsSelectsSettingsRoute() {
    let model = AppModel()

    model.openSettings()

    #expect(model.route == .settings)
}

@MainActor
@Test func openNewSessionSelectsNewSessionRoute() {
    let model = AppModel()
    model.route = .settings

    model.openNewSession()

    #expect(model.route == .newSession)
}

@MainActor
@Test func openSearchPresentsSearchWithoutChangingRoute() {
    let model = AppModel()
    model.route = .session("/tmp/session.jsonl")

    model.openSearch()

    #expect(model.isSearchPresented)
    #expect(model.route == .session("/tmp/session.jsonl"))
}

@MainActor
@Test func rapidTransitionsRetainEveryUnconfirmedSessionUntilItsOriginatingManagerReportsExit() async throws {
    let harness = ModelLifecycleHarness()
    let model = harness.makeModel()
    await model.bootstrap()

    model.openSession(modelSession(path: "/tmp/model-owner-a.jsonl"))
    let ownerA = try #require(await waitForActiveSession(model, path: "/tmp/model-owner-a.jsonl"))
    await ownerA.computerUse.enable()
    #expect(ownerA.computerUse.phase == .ready)

    model.openSession(modelSession(path: "/tmp/model-skipped-b.jsonl"))
    model.openSession(modelSession(path: "/tmp/model-owner-c.jsonl"))
    let ownerC = try #require(await waitForActiveSession(model, path: "/tmp/model-owner-c.jsonl"))
    await ownerC.computerUse.enable()
    #expect(ownerC.computerUse.phase == .ready)

    model.openSession(modelSession(path: "/tmp/model-owner-d.jsonl"))
    _ = try #require(await waitForActiveSession(model, path: "/tmp/model-owner-d.jsonl"))

    #expect(await harness.waitForReleasedOwnerCount(2))
    #expect(harness.logs[0].count("registry.release") == 1)
    #expect(harness.logs[1].count("registry.release") == 1)
    await harness.closeManagers()
}

@MainActor
@Test func installationReplacementKeepsTheOriginatingManagerWatcherAndSafetyHandle() async throws {
    let harness = ModelLifecycleHarness()
    let model = harness.makeModel()
    await model.bootstrap()

    let path = "/tmp/model-install-owner.jsonl"
    model.openSession(modelSession(path: path))
    let owner = try #require(await waitForActiveSession(model, path: path))
    await owner.computerUse.enable()
    #expect(owner.computerUse.phase == .ready)
    let originalManager = try #require(harness.managers.first)

    await model.useOmp(at: URL(filePath: "/tmp/replacement-omp"))

    #expect(harness.managers.count == 2)
    #expect(await originalManager.handle(for: path) != nil)
    #expect(await harness.waitForReleasedOwnerCount(1))
    #expect(harness.logs[0].count("registry.release") == 1)
    #expect(await originalManager.handle(for: path) == nil)
    await harness.closeManagers()
}

@MainActor
@Test func reopeningASafetyOwnedPathReleasesTheRetiringOwnerOnConfirmedDeath() async throws {
    let harness = ModelLifecycleHarness()
    let model = harness.makeModel()
    await model.bootstrap()

    let path = "/tmp/model-reopened-owner.jsonl"
    model.openSession(modelSession(path: path))
    let retiringOwner = try #require(await waitForActiveSession(model, path: path))
    await retiringOwner.computerUse.enable()
    #expect(retiringOwner.computerUse.phase == .ready)

    model.openSession(modelSession(path: path))
    _ = try #require(await waitForActiveSession(model, path: path))

    #expect(await harness.waitForReleasedOwnerCount(1))
    #expect(harness.logs[0].count("registry.release") == 1)
    await harness.closeManagers()
}

@MainActor
@Test func confirmedExitNotifiesEveryRetiringAndActiveOwnerOfTheSameHandle() async throws {
    let harness = ModelLifecycleHarness(mode: "multi-owner-delayed-exit")
    let model = harness.makeModel()
    await model.bootstrap()

    let path = "/tmp/model-multiple-reopened-owners.jsonl"
    model.openSession(modelSession(path: path))
    var ownerA: SessionController? = await waitForActiveSession(model, path: path)
    await ownerA?.computerUse.enable()
    #expect(ownerA?.computerUse.phase == .ready)

    model.openSession(modelSession(path: path))
    var ownerB: SessionController? = await waitForActiveSession(model, path: path)
    #expect(ownerB?.computerUse.isAwaitingConfirmedProcessExit == true)

    model.openSession(modelSession(path: path))
    let activeOwner = try #require(await waitForActiveSession(model, path: path))
    #expect(activeOwner.computerUse.isAwaitingConfirmedProcessExit)

    weak let weakOwnerA = ownerA
    weak let weakOwnerB = ownerB
    ownerA = nil
    ownerB = nil

    #expect(await waitForStoppedSession(activeOwner))
    #expect(activeOwner.isRecoveryPresented)
    #expect(!activeOwner.computerUse.isAwaitingConfirmedProcessExit)
    #expect(await harness.waitForReleasedOwnerCount(1))
    #expect(harness.logs[0].count("registry.release") == 1)
    #expect(await waitForDeallocation { weakOwnerA == nil && weakOwnerB == nil })
    await harness.closeManagers()
}

@MainActor
@Test func bufferedOldExitDoesNotStopANewHandleForTheSamePath() async throws {
    let cleanupGate = ModelCleanupGate()
    let harness = ModelLifecycleHarness(
        mode: "delayed-exit-on-disable",
        cleanupGate: cleanupGate)
    let model = harness.makeModel()
    await model.bootstrap()

    let blockerPath = "/tmp/model-buffer-blocker.jsonl"
    model.openSession(modelSession(path: blockerPath))
    let blocker = try #require(await waitForActiveSession(model, path: blockerPath))
    await blocker.computerUse.enable()

    let reopenedPath = "/tmp/model-buffered-old-exit.jsonl"
    model.openSession(modelSession(path: reopenedPath))
    let oldOwner = try #require(await waitForActiveSession(model, path: reopenedPath))
    let manager = try #require(harness.managers.first)
    let oldHandle = try #require(await manager.handle(for: reopenedPath))
    #expect(await cleanupGate.waitUntilEntered())
    await oldOwner.computerUse.enable()

    model.openNewSession()
    #expect(await waitForHandleRemoval(manager, path: reopenedPath))
    model.openSession(modelSession(path: reopenedPath))
    let newOwner = try #require(await waitForActiveSession(model, path: reopenedPath))
    let newHandle = try #require(await manager.handle(for: reopenedPath))
    #expect(newOwner !== oldOwner)
    #expect(newHandle.generation != oldHandle.generation)
    #expect(newOwner.ownsProcess(from: manager, generation: newHandle.generation))
    #expect(!newOwner.ownsProcess(from: manager, generation: oldHandle.generation))
    #expect(!newOwner.isRecoveryPresented)
    cleanupGate.open()

    #expect(await harness.waitForReleasedOwnerCount(2))
    try await Task.sleep(for: .milliseconds(200))
    #expect(!newOwner.isRecoveryPresented)
    if case .stopped = newOwner.runtimeState {
        Issue.record("the buffered old-generation exit stopped the reopened handle")
    }
    await harness.closeManagers()
}

@MainActor
@Test func exitFanoutRemovesAnActiveOwnerThatRetiresDuringEarlierCleanup() async throws {
    let cleanupGate = ModelCleanupGate()
    let harness = ModelLifecycleHarness(
        mode: "multi-owner-delayed-exit",
        cleanupGate: cleanupGate)
    let model = harness.makeModel()
    await model.bootstrap()

    let path = "/tmp/model-reentrant-exit-owner.jsonl"
    model.openSession(modelSession(path: path))
    var ownerA: SessionController? = await waitForActiveSession(model, path: path)
    await ownerA?.computerUse.enable()

    model.openSession(modelSession(path: path))
    var ownerB: SessionController? = await waitForActiveSession(model, path: path)
    #expect(ownerB?.computerUse.isAwaitingConfirmedProcessExit == true)
    #expect(await cleanupGate.waitUntilEntered())

    model.openSession(modelSession(path: path))
    let newOwner = try #require(await waitForActiveSession(model, path: path))
    #expect(newOwner !== ownerB)
    weak let weakOwnerA = ownerA
    weak let weakOwnerB = ownerB
    ownerA = nil
    ownerB = nil
    cleanupGate.open()

    #expect(await harness.waitForReleasedOwnerCount(1))
    #expect(await waitForDeallocation { weakOwnerA == nil && weakOwnerB == nil })
    #expect(harness.logs[0].count("registry.release") == 1)
    await harness.closeManagers()
}

@MainActor
private final class ModelLifecycleHarness {
    private(set) var logs: [ModelLifecycleLog] = []
    private(set) var managers: [SessionProcessManager] = []
    private let mode: String
    private let cleanupGate: ModelCleanupGate?

    init(
        mode: String = "delayed-exit-on-disable",
        cleanupGate: ModelCleanupGate? = nil
    ) {
        self.mode = mode
        self.cleanupGate = cleanupGate
    }

    func makeModel() -> AppModel {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "tenx-model-lifecycle-\(UUID().uuidString)")
        let dependencies = AppDependencies(
            ompLocator: FixedModelOmpLocator(),
            sessionLibrary: SessionLibrary(root: root),
            computerUseRegistry: ComputerUseRegistry(),
            makeProcessManager: { [weak self] _ in
                let manager = modelLifecycleManager(mode: self?.mode ?? "delayed-exit-on-disable")
                self?.managers.append(manager)
                return manager
            },
            makeSessionController: { [weak self] processManager, _ in
                let log = ModelLifecycleLog()
                self?.logs.append(log)
                let computerUse = ComputerUseController(
                    sessionID: UUID().uuidString,
                    lifecycle: .modelLifecycle(log, cleanupGate: self?.cleanupGate),
                    preference: .automatic)
                return SessionController(
                    processManager: processManager,
                    computerUse: computerUse,
                    terminateProcess: { _ in false })
            })
        return AppModel(dependencies: dependencies)
    }

    func waitForReleasedOwnerCount(_ expected: Int) async -> Bool {
        for _ in 0..<150 {
            let released = logs.filter { $0.count("registry.release") == 1 }.count
            if released >= expected { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    func closeManagers() async {
        for manager in managers { await manager.closeAll() }
    }
}

@MainActor
private final class ModelCleanupGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false
    private(set) var didEnter = false

    func wait() async {
        guard !isOpen else { return }
        didEnter = true
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }

    func waitUntilEntered() async -> Bool {
        for _ in 0..<150 {
            if didEnter { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }
}

@MainActor
private final class ModelLifecycleLog {
    private var values: [String] = []

    func append(_ value: String) { values.append(value) }
    func count(_ value: String) -> Int { values.filter { $0 == value }.count }
}

private struct FixedModelOmpLocator: OmpLocating {
    func locate(preferredURL: URL?) async -> OmpInstallation? {
        OmpInstallation(
            executableURL: preferredURL ?? URL(filePath: "/tmp/fake-omp"),
            version: "test")
    }
}

private func modelLifecycleManager(mode: String) -> SessionProcessManager {
    SessionProcessManager(clientFactory: { configuration in
        var updated = configuration
        updated.executable = "/usr/bin/env"
        updated.extraArguments = [
            "python3", modelFixtureURL.path,
            mode, "--computer-contract",
        ]
        updated.rawArgv = true
        updated.cwd = nil
        return RpcClient(configuration: updated)
    })
}

private let modelFixtureURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appending(path: "OmpKit/Tests/OmpKitTests/Fixtures/fake_server.py")

@MainActor
private func waitForActiveSession(_ model: AppModel, path: String) async -> SessionController? {
    for _ in 0..<100 {
        if let activeSession = model.activeSession,
           model.route == .session(path),
           activeSession.runtimeState != .loading {
            return activeSession
        }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return nil
}

@MainActor
private func waitForStoppedSession(_ controller: SessionController) async -> Bool {
    for _ in 0..<100 {
        if case .stopped = controller.runtimeState { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return false
}

private func waitForHandleRemoval(
    _ manager: SessionProcessManager,
    path: String
) async -> Bool {
    for _ in 0..<150 {
        if await manager.handle(for: path) == nil { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return false
}

@MainActor
private func waitForDeallocation(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<100 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return false
}

private func modelSession(path: String) -> SessionMetadata {
    SessionMetadata(
        path: path,
        sessionId: path,
        cwd: "/tmp",
        title: nil,
        created: Date(),
        modified: Date(),
        sizeBytes: 0,
        status: .unknown)
}

private extension ComputerUseControllerLifecycle {
    static func modelLifecycle(
        _ log: ModelLifecycleLog,
        cleanupGate: ModelCleanupGate? = nil
    ) -> Self {
        Self(
            activate: { _ in log.append("registry.activate") },
            release: { _ in log.append("registry.release") },
            acquireLease: { _ in log.append("lease.acquire") },
            releaseLease: { log.append("lease.release") },
            prepare: { _ in
                log.append("desktop.prepare")
                return PreparedAgentDesktop(
                    provider: .aeroSpace,
                    workspaceID: "workspace",
                    capabilities: .isolated)
            },
            probe: { _, operation in try await operation(nil, nil) },
            cleanup: { _ in
                await cleanupGate?.wait()
                log.append("desktop.cleanup")
                return CleanupReport(
                    preservedApplicationNames: [],
                    restoredWindowCount: 0)
            },
            releaseDesktop: { _ in log.append("desktop.release") })
    }
}
