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

    await controller.handleHostToolCall(HostToolCall(
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

    await controller.handleHostToolCall(HostToolCall(
        id: "borrow", toolCallID: "tool-borrow", name: "agent_desktop",
        arguments: .object(["action": .string("borrow"), "windowId": .string("window-1")])))
    await controller.handleHostToolCancel(targetID: "cancelled")
    await controller.handleHostToolCall(HostToolCall(
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

private enum TestFailure: Error { case failed }

@MainActor private final class LifecycleLog {
    private(set) var values: [String] = []
    func append(_ value: String) { values.append(value) }
    func reset() { values = [] }
}

private actor ControllerRPC: ComputerUseRPC {
    private let log: LifecycleLog
    private let enableError: (any Error)?
    private let reportedState: ComputerUseRPCState

    init(log: LifecycleLog, enableError: (any Error)? = nil, state: ComputerUseRPCState = ComputerUseRPCState(enabled: false, foregroundPolicy: .requireHandoff)) {
        self.log = log
        self.enableError = enableError
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
        if enabled, let enableError { throw enableError }
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
    }

    func sendHostToolResult(id: String, result: JSONValue, isError: Bool) async throws {
        await log.append("rpc.hostResult.\(id).\(isError ? "error" : "success")")
    }

    func abort() async throws { await log.append("rpc.abort") }
}

private extension ComputerUseControllerLifecycle {
    static func recording(_ log: LifecycleLog) -> Self {
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
            releaseDesktop: { _ in log.append("desktop.release") })
    }
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
