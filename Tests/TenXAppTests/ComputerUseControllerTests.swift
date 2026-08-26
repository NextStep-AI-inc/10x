import Foundation
import OmpKit
import Testing
@testable import TenXApp

@MainActor @Test func enablePreparesTheDesktopBeforeEnablingComputerUse() async {
    let log = LifecycleLog()
    let rpc = ControllerRPC(log: log)
    let controller = ComputerUseController(
        sessionID: "session-a",
        lifecycle: .recording(log),
        preference: .automatic)
    controller.attach(rpc: rpc, sessionPath: "/tmp/session-a.jsonl")

    await controller.enable()

    #expect(controller.phase == .ready)
    #expect(log.values == [
        "registry.activate", "lease.acquire", "desktop.prepare", "rpc.enable",
        "rpc.availability", "rpc.hostTools", "rpc.probe", "desktop.probe",
    ])
}

@MainActor @Test func failedEnableReleasesOnlyTheResourcesItAcquiredInReverseOrder() async {
    let log = LifecycleLog()
    let rpc = ControllerRPC(log: log, enableError: TestFailure.failed)
    let controller = ComputerUseController(
        sessionID: "session-b",
        lifecycle: .recording(log),
        preference: .automatic)
    controller.attach(rpc: rpc, sessionPath: "/tmp/session-b.jsonl")

    await controller.enable()

    #expect(controller.phase == .unavailable(
        message: "Computer use could not start", isBestEffortAvailable: false))
    #expect(log.values == [
        "registry.activate", "lease.acquire", "desktop.prepare", "rpc.enable",
        "rpc.disable", "desktop.cleanup", "desktop.release", "lease.release", "registry.release",
    ])
}

@MainActor @Test func watcherStartupFailureRollsBackRemoteAuthorizationAndResources() async {
    let log = LifecycleLog()
    let rpc = ControllerRPC(log: log)
    let controller = ComputerUseController(
        sessionID: "session-watcher-start",
        lifecycle: .recording(log, watchWindows: { _ in
            throw AgentDesktopProviderError.operationFailed(.aeroSpace)
        }),
        preference: .automatic)
    controller.attach(rpc: rpc, sessionPath: "/tmp/session-watcher-start.jsonl")

    await controller.enable()

    #expect(controller.phase == .unavailable(
        message: "Computer use could not start", isBestEffortAvailable: false))
    #expect(log.values.suffix(6) == [
        "rpc.hostTools.clear", "rpc.disable", "desktop.cleanup", "desktop.release", "lease.release",
        "registry.release",
    ])
    #expect(log.values.last == "registry.release")
    #expect(await rpc.remoteSnapshot().enabled == false)
    #expect(await rpc.remoteSnapshot().toolNames.isEmpty)
}

@MainActor @Test func postEnableWatcherFailureAbortsAndFailsClosed() async {
    let log = LifecycleLog()
    let rpc = ControllerRPC(log: log)
    let source = AsyncStream<AgentWindowEvent>.makeStream()
    let controller = ComputerUseController(
        sessionID: "session-watcher-runtime",
        lifecycle: .recording(log, watchWindows: { _ in source.stream }),
        preference: .automatic)
    controller.attach(rpc: rpc, sessionPath: "/tmp/session-watcher-runtime.jsonl")
    await controller.enable()
    #expect(controller.phase == .ready)
    controller.handleToolStarted(.object([
        "toolName": .string("computer"), "target": .string("TextEdit"),
    ]))
    log.reset()

    source.continuation.yield(.failed(.operationFailed(.aeroSpace)))
    for _ in 0..<100 where !log.values.contains("rpc.abort") {
        try? await Task.sleep(for: .milliseconds(5))
    }
    controller.handleToolEnded(.object(["toolName": .string("computer")]))
    for _ in 0..<100 where controller.phase != .unavailable(
        message: "Computer use stopped because its session could not be secured",
        isBestEffortAvailable: false)
    {
        try? await Task.sleep(for: .milliseconds(5))
    }

    #expect(controller.phase == .unavailable(
        message: "Computer use stopped because its session could not be secured",
        isBestEffortAvailable: false))
    #expect(log.values.contains("rpc.abort"))
    #expect(log.values.contains("rpc.hostTools.clear"))
    #expect(log.values.contains("rpc.disable"))
    #expect(log.values.contains("desktop.cleanup"))
    #expect(log.values.last == "registry.release")
}

@MainActor @Test func concurrentStopsRunOneCleanupAndLeaveTheSessionOff() async {
    let log = LifecycleLog()
    let rpc = ControllerRPC(log: log)
    let controller = ComputerUseController(
        sessionID: "session-c",
        lifecycle: .recording(log),
        preference: .automatic)
    controller.attach(rpc: rpc, sessionPath: "/tmp/session-c.jsonl")
    await controller.enable()
    log.reset()

    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<3 {
            group.addTask { await controller.stopComputerUse() }
        }
    }

    #expect(controller.phase == .off)
    #expect(log.values == [
        "rpc.hostTools.clear", "rpc.disable", "desktop.cleanup", "desktop.release", "lease.release", "registry.release",
    ])
}

@MainActor @Test func stopBoundsAnUnfinishedComputerCallAndIgnoresLateToolEvents() async {
    let log = LifecycleLog()
    let rpc = ControllerRPC(log: log)
    let controller = ComputerUseController(
        sessionID: "session-timeout", lifecycle: .recording(log), preference: .automatic)
    controller.attach(rpc: rpc, sessionPath: "/tmp/session-timeout.jsonl")
    await controller.enable()
    controller.handleToolStarted(.object([
        "toolName": .string("computer"), "target": .string("TextEdit"),
    ]))
    let start = ContinuousClock.now

    await controller.stopComputerUse()
    let elapsed = start.duration(to: .now)
    controller.handleToolEnded(.object(["toolName": .string("computer")]))

    #expect(elapsed <= .seconds(2.1))
    #expect(controller.phase == .unavailable(
        message: "Computer use stopped because its session could not be secured",
        isBestEffortAvailable: false))
    #expect(log.values.contains("rpc.abort"))
}

@MainActor @Test func stopDeniesPendingHandoffBeforeAbort() async {
    let log = LifecycleLog()
    let rpc = ControllerRPC(log: log)
    let controller = ComputerUseController(
        sessionID: "session-handoff", lifecycle: .recording(log), preference: .automatic)
    controller.attach(rpc: rpc, sessionPath: "/tmp/session-handoff.jsonl")
    await controller.enable()
    controller.handleToolStarted(.object([
        "toolName": .string("computer"),
        "target": .string("TextEdit"),
    ]))
    controller.requestHandoff(
        id: "handoff-1",
        target: "TextEdit",
        reason: "Background keyboard delivery is unavailable")
    log.reset()

    await controller.stopComputerUse()

    #expect(Array(log.values.prefix(2)) == [
        "rpc.handoff.handoff-1.false",
        "rpc.abort",
    ])
}

@MainActor @Test func approvingHandoffOpensDesktopBeforeOneResponse() async {
    let log = LifecycleLog()
    let rpc = ControllerRPC(log: log)
    let controller = ComputerUseController(
        sessionID: "session-approve", lifecycle: .recording(log), preference: .automatic)
    controller.attach(rpc: rpc, sessionPath: "/tmp/session-approve.jsonl")
    await controller.enable()
    controller.handleToolStarted(.object([
        "toolName": .string("computer"),
        "target": .string("TextEdit"),
    ]))
    controller.requestHandoff(
        id: "handoff-approve",
        target: "TextEdit",
        reason: "Background keyboard delivery is unavailable")
    log.reset()

    #expect(await controller.respondToHandoff(id: "handoff-approve", approved: true))
    #expect(await !controller.respondToHandoff(id: "handoff-approve", approved: true))

    #expect(log.values == [
        "desktop.openVisibly",
        "rpc.handoff.handoff-approve.true",
    ])
    #expect(controller.phase == .controlling(target: "TextEdit"))
}

@MainActor @Test func aSecondHandoffCannotReplaceThePendingRequest() async {
    let log = LifecycleLog()
    let rpc = ControllerRPC(log: log)
    let controller = ComputerUseController(
        sessionID: "session-pending", lifecycle: .recording(log), preference: .automatic)
    controller.attach(rpc: rpc, sessionPath: "/tmp/session-pending.jsonl")
    await controller.enable()
    controller.requestHandoff(id: "handoff-first", target: "TextEdit", reason: "Input required")
    controller.requestHandoff(id: "handoff-second", target: "Safari", reason: "Input required")
    log.reset()

    await controller.stopComputerUse()

    #expect(log.values.first == "rpc.handoff.handoff-first.false")
    #expect(!log.values.contains("rpc.handoff.handoff-second.false"))
}

@MainActor @Test func exactAgentDesktopHostToolRoutesAndUnknownToolGetsOneError() async {
    let log = LifecycleLog()
    let rpc = ControllerRPC(log: log)
    let controller = ComputerUseController(
        sessionID: "session-d",
        lifecycle: .recording(log),
        preference: .automatic)
    controller.attach(rpc: rpc, sessionPath: "/tmp/session-d.jsonl")
    await controller.enable()
    log.reset()

    controller.handleHostToolCall(HostToolCall(
        id: "unknown", toolCallID: "unknown-tool", name: "other_tool", arguments: .object([:])))
    try? await Task.sleep(for: .milliseconds(25))

    #expect(log.values == ["rpc.hostResult.unknown.error"])
}

@MainActor @Test func exactAgentDesktopBorrowAndCancellationRouteToTheRegisteredHostTool() async {
    let log = LifecycleLog()
    let rpc = ControllerRPC(log: log)
    let provider = ControllerHostProvider()
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let controller = ComputerUseController(
        registry: ComputerUseRegistry(),
        lease: ComputerUseLease(directory: directory),
        coordinator: AgentDesktopCoordinator(providers: [provider]),
        preference: .backgroundOnly)
    controller.attach(rpc: rpc, sessionPath: "/tmp/session-host.jsonl")
    await controller.enable(safetyMode: .legacyBestEffort)
    log.reset()

    controller.handleHostToolCall(HostToolCall(
        id: "borrow", toolCallID: "tool-borrow", name: "agent_desktop",
        arguments: .object(["action": .string("borrow"), "windowId": .string("window-1")])))
    controller.handleHostToolCancel(targetID: "cancelled")
    controller.handleHostToolCall(HostToolCall(
        id: "cancelled", toolCallID: "tool-cancelled", name: "agent_desktop",
        arguments: .object(["action": .string("borrow"), "windowId": .string("window-1")])))
    try? await Task.sleep(for: .milliseconds(50))

    #expect(Set(log.values) == Set([
        "rpc.hostResult.borrow.success", "rpc.hostResult.cancelled.error",
    ]))
    #expect(log.values.count == 2)
}

@MainActor @Test func reopeningAnEnabledOMPComputerSessionDisablesItAndStaysOff() async {
    let log = LifecycleLog()
    let rpc = ControllerRPC(log: log, state: ComputerUseRPCState(
        enabled: true, foregroundPolicy: .requireHandoff))
    let controller = ComputerUseController(
        sessionID: "session-e",
        lifecycle: .recording(log),
        preference: .automatic)

    await controller.attachAndReconcile(rpc: rpc, sessionPath: "/tmp/session-e.jsonl")

    #expect(controller.phase == .off)
    #expect(log.values == ["rpc.state", "rpc.disable"])
}

@MainActor @Test func reportedComputerPermissionLossFailsClosed() async {
    let log = LifecycleLog()
    let rpc = ControllerRPC(log: log)
    let controller = ComputerUseController(
        sessionID: "session-permission", lifecycle: .recording(log), preference: .automatic)
    controller.attach(rpc: rpc, sessionPath: "/tmp/session-permission.jsonl")
    await controller.enable()

    await controller.handlePermissionLoss()

    #expect(controller.phase == .unavailable(
        message: "Computer use stopped because its session could not be secured", isBestEffortAvailable: false))
}

@MainActor @Test func computerToolEventsMustMatchTheExactToolName() async {
    let log = LifecycleLog()
    let rpc = ControllerRPC(log: log)
    let controller = ComputerUseController(
        sessionID: "session-f", lifecycle: .recording(log), preference: .automatic)
    controller.attach(rpc: rpc, sessionPath: "/tmp/session-f.jsonl")
    await controller.enable()

    controller.handleToolStarted(.object(["toolName": .string("computer_file")]))
    #expect(controller.phase == .ready)
    controller.handleToolStarted(.object(["toolName": .string("computer"), "target": .string("TextEdit")]))
    #expect(controller.phase == .controlling(target: "TextEdit"))
}

@MainActor @Test func focusIsolationRejectsAPreparedBackgroundDesktop() async {
    let log = LifecycleLog()
    let rpc = ControllerRPC(log: log)
    let lifecycle = ComputerUseControllerLifecycle(
        activate: { _ in log.append("registry.activate") },
        release: { _ in log.append("registry.release") },
        acquireLease: { _ in log.append("lease.acquire") },
        releaseLease: { log.append("lease.release") },
        prepare: { _ in
            log.append("desktop.prepare")
            return PreparedAgentDesktop(
                provider: .background, workspaceID: nil, capabilities: .background)
        },
        probe: { _, _ in probeResult() },
        cleanup: { _ in CleanupReport(preservedApplicationNames: [], restoredWindowCount: 0) },
        releaseDesktop: { _ in log.append("desktop.release") })
    let controller = ComputerUseController(
        sessionID: "session-isolation", lifecycle: lifecycle, preference: .automatic)
    controller.attach(rpc: rpc, sessionPath: "/tmp/session-isolation.jsonl")

    await controller.enable()

    #expect(controller.phase == .unavailable(
        message: "Computer use could not start", isBestEffortAvailable: false))
    #expect(log.values == [
        "registry.activate", "lease.acquire", "desktop.prepare", "lease.release", "registry.release",
    ])
}

@MainActor @Test func stopDuringDelayedPrepareReleasesTheLateDesktopWithoutEnablingOMP() async {
    let log = LifecycleLog()
    let rpc = ControllerRPC(log: log)
    let prepareGate = PrepareGate()
    let lifecycle = delayedPrepareLifecycle(log, gate: prepareGate)
    let controller = ComputerUseController(
        sessionID: "session-delayed-prepare", lifecycle: lifecycle, preference: .automatic)
    controller.attach(rpc: rpc, sessionPath: "/tmp/session-delayed-prepare.jsonl")

    let enabling = Task { await controller.enable() }
    await prepareGate.waitUntilStarted()
    #expect(log.values.contains("desktop.prepare.started"))
    await controller.stopComputerUse()
    await prepareGate.open()
    await enabling.value

    #expect(log.values.contains("desktop.release"))
    #expect(!log.values.contains("rpc.enable"))
    #expect(controller.phase == .off)
}

@MainActor @Test func stopDuringDelayedEnableCannotRegisterToolsOrReviveReadyState() async {
    let log = LifecycleLog()
    let rpc = ControllerRPC(log: log, enableDelay: .milliseconds(120))
    let controller = ComputerUseController(
        sessionID: "session-delayed-enable", lifecycle: .recording(log), preference: .automatic)
    controller.attach(rpc: rpc, sessionPath: "/tmp/session-delayed-enable.jsonl")

    let enabling = Task { await controller.enable() }
    try? await Task.sleep(for: .milliseconds(20))
    await controller.stopComputerUse()
    await enabling.value

    #expect(!log.values.contains("rpc.hostTools"))
    #expect(controller.phase == .off)
}

@MainActor @Test func stopWaitsForAnInFlightEnableBeforeReversingRemoteAuthorization() async {
    let log = LifecycleLog()
    let rpc = ControllerRPC(log: log, nonCancellingEnableDelay: .milliseconds(120))
    let controller = ComputerUseController(
        sessionID: "session-stateful-enable", lifecycle: .recording(log), preference: .automatic)
    controller.attach(rpc: rpc, sessionPath: "/tmp/session-stateful-enable.jsonl")

    let enabling = Task { await controller.enable() }
    try? await Task.sleep(for: .milliseconds(20))
    await controller.stopComputerUse()
    await enabling.value

    let remote = await rpc.remoteSnapshot()
    #expect(remote.enabled == false)
    #expect(remote.toolNames == [])
    #expect(log.values.last == "registry.release")
}

@MainActor @Test func stopWaitsForTheUnderlyingMutationAfterRequestCancellationReturns() async throws {
    let log = LifecycleLog()
    let rpc = ControllerRPC(
        log: log,
        cancellationLeakedEnableDelay: .milliseconds(120))
    let controller = ComputerUseController(
        sessionID: "session-delayed-write",
        lifecycle: .recording(log),
        preference: .automatic)
    controller.attach(rpc: rpc, sessionPath: "/tmp/session-delayed-write.jsonl")

    let enabling = Task { await controller.enable() }
    for _ in 0..<20 where !log.values.contains("rpc.enable") {
        try? await Task.sleep(for: .milliseconds(5))
    }
    #expect(log.values.contains("rpc.enable"))

    await controller.stopComputerUse()
    await enabling.value
    try? await Task.sleep(for: .milliseconds(160))

    let remote = await rpc.remoteSnapshot()
    #expect(remote.enabled == false)
    #expect(remote.toolNames == [])
    let enableWrite = try #require(log.values.firstIndex(of: "rpc.enable.write"))
    let disable = try #require(log.values.firstIndex(of: "rpc.disable"))
    #expect(enableWrite < disable)
    #expect(log.values.last == "registry.release")
}

@MainActor @Test func unconfirmedForcedShutdownRetainsComputerResourcesForTheExitOwner() async {
    let log = LifecycleLog()
    let rpc = ControllerRPC(log: log, disableError: TestFailure.failed)
    let controller = ComputerUseController(
        sessionID: "session-unconfirmed-stop", lifecycle: .recording(log), preference: .automatic)
    controller.attach(
        rpc: rpc,
        sessionPath: "/tmp/session-unconfirmed-stop.jsonl",
        terminateProcess: { _ in false })
    await controller.enable()

    await controller.stopComputerUse()

    #expect(controller.isAwaitingConfirmedProcessExit)
    #expect(!log.values.contains("lease.release"))
    #expect(!log.values.contains("registry.release"))
}

@MainActor @Test func processExitRacingSlowCleanupSharesOneRetainedCleanupTask() async {
    let log = LifecycleLog()
    let gate = CleanupGate()
    let rpc = ControllerRPC(log: log)
    let controller = ComputerUseController(
        sessionID: "session-slow-cleanup",
        lifecycle: .gatedCleanup(log, gate: gate),
        preference: .automatic)
    controller.attach(rpc: rpc, sessionPath: "/tmp/session-slow-cleanup.jsonl")
    await controller.enable()
    log.reset()

    let started = ContinuousClock.now
    let stopping = Task { await controller.stopComputerUse() }
    for _ in 0..<40 where await gate.cleanupCount() == 0 {
        try? await Task.sleep(for: .milliseconds(5))
    }
    #expect(await gate.cleanupCount() == 1)
    let processExit = Task { await controller.handleProcessTerminated() }

    await stopping.value
    #expect(started.duration(to: .now) <= .seconds(2.2))
    #expect(controller.phase == .unavailable(
        message: "Computer use stopped because its session could not be secured",
        isBestEffortAvailable: false))
    #expect(await gate.cleanupCount() == 1)
    #expect(!log.values.contains("lease.release"))
    #expect(!log.values.contains("registry.release"))

    await gate.open()
    await processExit.value

    #expect(await gate.cleanupCount() == 1)
    #expect(log.values.filter { $0 == "desktop.release" }.count == 1)
    #expect(log.values.filter { $0 == "lease.release" }.count == 1)
    #expect(log.values.filter { $0 == "registry.release" }.count == 1)
    #expect(log.values.last == "registry.release")
}

@MainActor @Test func structuredAvailabilityRefreshReissuesRequireHandoffAuthorization() async {
    let log = LifecycleLog()
    let rpc = ControllerRPC(log: log)
    let controller = ComputerUseController(
        sessionID: "session-refresh", lifecycle: .recording(log), preference: .automatic)
    controller.attach(rpc: rpc, sessionPath: "/tmp/session-refresh.jsonl")
    await controller.enable()
    log.reset()

    await controller.refreshAvailability()

    #expect(controller.phase == .ready)
    #expect(log.values == ["rpc.availability", "rpc.enable"])
}

@MainActor @Test func legacyAvailabilityRefreshFailsClosedRatherThanClaimingModelSupport() async {
    let log = LifecycleLog()
    let rpc = ControllerRPC(log: log)
    let controller = ComputerUseController(
        sessionID: "session-legacy-refresh", lifecycle: .recording(log), preference: .automatic)
    controller.attach(rpc: rpc, sessionPath: "/tmp/session-legacy-refresh.jsonl")
    await controller.enable(safetyMode: .legacyBestEffort)

    await controller.refreshAvailability()

    #expect(controller.phase == .unavailable(
        message: "Computer use stopped because its session could not be secured",
        isBestEffortAvailable: false))
}

@MainActor @Test func controllerDeinitCancelsItsManifestWatcher() async {
    let log = LifecycleLog()
    let rpc = ControllerRPC(log: log)
    let provider = DeinitWatcherProvider()
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }

    var controller: ComputerUseController? = ComputerUseController(
        registry: ComputerUseRegistry(),
        lease: ComputerUseLease(directory: directory),
        coordinator: AgentDesktopCoordinator(providers: [provider]),
        preference: .backgroundOnly)
    controller?.attach(rpc: rpc, sessionPath: "/tmp/session-deinit.jsonl")
    await controller?.enable(safetyMode: .legacyBestEffort)
    #expect(controller?.phase == .ready)

    weak var releasedController = controller
    controller = nil
    for _ in 0..<20 {
        if await provider.watcherDidTerminate() { break }
        try? await Task.sleep(for: .milliseconds(10))
    }

    #expect(releasedController == nil)
    #expect(await provider.watcherDidTerminate())
}

private enum TestFailure: Error { case failed }

@MainActor private final class LifecycleLog {
    private(set) var values: [String] = []
    func append(_ value: String) { values.append(value) }
    func reset() { values = [] }
}

private actor ControllerRPC: ComputerUseRPC, ComputerForegroundHandoffResponding {
    private let log: LifecycleLog
    private let enableError: (any Error)?
    private let disableError: (any Error)?
    private let enableDelay: Duration?
    private let nonCancellingEnableDelay: Duration?
    private let cancellationLeakedEnableDelay: Duration?
    private let reportedState: ComputerUseRPCState
    private var remoteEnabled = false
    private var remoteToolNames: [String] = []

    init(log: LifecycleLog, enableError: (any Error)? = nil, disableError: (any Error)? = nil, enableDelay: Duration? = nil, nonCancellingEnableDelay: Duration? = nil, cancellationLeakedEnableDelay: Duration? = nil, state: ComputerUseRPCState = ComputerUseRPCState(enabled: false, foregroundPolicy: .requireHandoff)) {
        self.log = log
        self.enableError = enableError
        self.disableError = disableError
        self.enableDelay = enableDelay
        self.nonCancellingEnableDelay = nonCancellingEnableDelay
        self.cancellationLeakedEnableDelay = cancellationLeakedEnableDelay
        reportedState = state
    }

    func state() async throws -> ComputerUseRPCState {
        await log.append("rpc.state")
        return reportedState
    }

    func availability() async throws -> ComputerUseAvailability {
        await log.append("rpc.availability")
        return ComputerUseAvailability(json: .object([
            "model": .object(["id": .string("fake")]),
            "computerUse": .object([
                "enabled": .bool(true),
                "foregroundPolicy": .string("require-handoff"),
            ]),
        ]))!
    }

    func setComputerUse(enabled: Bool, policy: ComputerForegroundPolicy) async throws -> ComputerUseRPCState {
        await log.append(enabled ? "rpc.enable" : "rpc.disable")
        if enabled, let enableDelay { try await Task.sleep(for: enableDelay) }
        if enabled, let nonCancellingEnableDelay { try? await Task.sleep(for: nonCancellingEnableDelay) }
        if enabled, let cancellationLeakedEnableDelay {
            do {
                try await Task.sleep(for: cancellationLeakedEnableDelay)
            } catch {
                Task {
                    try? await Task.sleep(for: cancellationLeakedEnableDelay)
                    await self.commitDelayedEnableWrite()
                }
                throw error
            }
            await log.append("rpc.enable.write")
        }
        if enabled, let enableError { throw enableError }
        if !enabled, let disableError { throw disableError }
        remoteEnabled = enabled
        return ComputerUseRPCState(enabled: enabled, foregroundPolicy: policy)
    }

    func setLegacyComputerUse(enabled: Bool) async throws {
        await log.append(enabled ? "rpc.legacy.enable" : "rpc.legacy.disable")
    }

    func probeComputerUse(target: String?, verificationText: String?) async throws -> ComputerProbeResult {
        await log.append("rpc.probe")
        return probeResult()
    }

    func setHostTools(_ definitions: [HostToolDefinition]) async throws {
        await log.append(definitions.isEmpty ? "rpc.hostTools.clear" : "rpc.hostTools")
        remoteToolNames = definitions.map(\.name)
    }

    func sendHostToolResult(id: String, result: JSONValue, isError: Bool) async throws {
        await log.append("rpc.hostResult.\(id).\(isError ? "error" : "success")")
    }

    func abort() async throws { await log.append("rpc.abort") }

    func respondToComputerForegroundHandoff(id: String, approved: Bool) async throws {
        await log.append("rpc.handoff.\(id).\(approved)")
    }

    func remoteSnapshot() -> (enabled: Bool, toolNames: [String]) {
        (remoteEnabled, remoteToolNames)
    }

    private func commitDelayedEnableWrite() async {
        remoteEnabled = true
        await log.append("rpc.enable.write")
    }
}

private extension ComputerUseControllerLifecycle {
    static func recording(
        _ log: LifecycleLog,
        watchWindows: @escaping @Sendable (PreparedAgentDesktop) async throws -> AsyncStream<AgentWindowEvent> = { _ in
            AsyncStream { $0.finish() }
        }
    ) -> Self {
        Self(
            activate: { _ in log.append("registry.activate") },
            release: { _ in log.append("registry.release") },
            acquireLease: { _ in log.append("lease.acquire") },
            releaseLease: { log.append("lease.release") },
            prepare: { _ in
                log.append("desktop.prepare")
                return PreparedAgentDesktop(
                    provider: .aeroSpace, workspaceID: "workspace", capabilities: .isolated)
            },
            probe: { _, operation in
                let result = try await operation(nil, nil)
                log.append("desktop.probe")
                return result
            },
            cleanup: { _ in
                log.append("desktop.cleanup")
                return CleanupReport(preservedApplicationNames: [], restoredWindowCount: 0)
            },
            watchWindows: watchWindows,
            openVisibly: { _ in log.append("desktop.openVisibly") },
            releaseDesktop: { _ in log.append("desktop.release") })
    }

    static func gatedCleanup(_ log: LifecycleLog, gate: CleanupGate) -> Self {
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
            probe: { _, operation in
                let result = try await operation(nil, nil)
                log.append("desktop.probe")
                return result
            },
            cleanup: { _ in
                await gate.wait()
                log.append("desktop.cleanup")
                return CleanupReport(
                    preservedApplicationNames: [],
                    restoredWindowCount: 0)
            },
            releaseDesktop: { _ in log.append("desktop.release") })
    }
}

private actor CleanupGate {
    private var isOpen = false
    private var count = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        count += 1
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func cleanupCount() -> Int { count }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

private actor PrepareGate {
    private var isOpen = false
    private var hasStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var openWaiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        hasStarted = true
        let pendingStartWaiters = startWaiters
        startWaiters.removeAll()
        for waiter in pendingStartWaiters { waiter.resume() }
        guard !isOpen else { return }
        await withCheckedContinuation { openWaiters.append($0) }
    }

    func waitUntilStarted() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func open() {
        isOpen = true
        let pendingOpenWaiters = openWaiters
        openWaiters.removeAll()
        for waiter in pendingOpenWaiters { waiter.resume() }
    }
}

@MainActor
private func delayedPrepareLifecycle(
    _ log: LifecycleLog,
    gate: PrepareGate
) -> ComputerUseControllerLifecycle {
    ComputerUseControllerLifecycle(
        activate: { _ in log.append("registry.activate") },
        release: { _ in log.append("registry.release") },
        acquireLease: { _ in log.append("lease.acquire") },
        releaseLease: { log.append("lease.release") },
        prepare: { _ in
            log.append("desktop.prepare.started")
            await gate.wait()
            log.append("desktop.prepare")
            return PreparedAgentDesktop(provider: .aeroSpace, workspaceID: "workspace", capabilities: .isolated)
        },
        probe: { _, _ in probeResult() },
        cleanup: { _ in
            log.append("desktop.cleanup")
            return CleanupReport(preservedApplicationNames: [], restoredWindowCount: 0)
        },
        releaseDesktop: { _ in log.append("desktop.release") })
}

private func probeResult() -> ComputerProbeResult {
    ComputerProbeResult(json: .object([
        "capabilities": .object([
            "backend": .string("macos"),
            "capturePermission": .string("granted"),
            "inputPermission": .string("granted"),
            "axPermission": .string("granted"),
        ]),
        "captureSucceeded": .bool(true),
        "backgroundInputSucceeded": .bool(true),
    ]))!
}

private actor ControllerHostProvider: AgentDesktopProvider {
    nonisolated let kind: AgentDesktopProviderKind = .background

    func probe() async -> ProviderProbe {
        ProviderProbe(availability: .healthy, integrationVersion: nil, capabilities: .background)
    }

    func prepare(sessionToken: String) async throws -> PreparedAgentDesktop {
        PreparedAgentDesktop(provider: kind, workspaceID: nil, capabilities: .background)
    }

    func listWindows() async throws -> [AgentWindow] {
        [AgentWindow(id: "window-1", processID: 1, app: "TextEdit", workspaceID: nil)]
    }

    func watchWindows() async throws -> AsyncStream<AgentWindowEvent> {
        AsyncStream { continuation in continuation.finish() }
    }

    func move(windowID: String, to workspaceID: String) async throws {}
    func restore(windowID: String, to workspaceID: String) async throws {}
    func openVisibly(workspaceID: String) async throws {}
    func release(workspaceID: String) async {}
}

private actor DeinitWatcherProvider: AgentDesktopProvider {
    nonisolated let kind: AgentDesktopProviderKind = .background
    private var continuation: AsyncStream<AgentWindowEvent>.Continuation?
    private var watcherTerminated = false

    func probe() async -> ProviderProbe {
        ProviderProbe(availability: .healthy, integrationVersion: nil, capabilities: .background)
    }

    func prepare(sessionToken: String) async throws -> PreparedAgentDesktop {
        PreparedAgentDesktop(provider: kind, workspaceID: nil, capabilities: .background)
    }

    func listWindows() async throws -> [AgentWindow] { [] }

    func watchWindows() async throws -> AsyncStream<AgentWindowEvent> {
        let stream = AsyncStream<AgentWindowEvent> { continuation in
            continuation.onTermination = { [weak self] _ in
                Task { await self?.recordWatcherTermination() }
            }
            self.continuation = continuation
        }
        return stream
    }

    func move(windowID: String, to workspaceID: String) async throws {}
    func restore(windowID: String, to workspaceID: String) async throws {}
    func openVisibly(workspaceID: String) async throws {}
    func release(workspaceID: String) async {}

    func watcherDidTerminate() -> Bool { watcherTerminated }
    private func recordWatcherTermination() { watcherTerminated = true }
}
