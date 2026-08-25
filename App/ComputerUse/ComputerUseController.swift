import Foundation
import Observation
import OmpKit

@MainActor
struct ComputerUseControllerLifecycle {
    let activate: (ComputerUseStopping) async -> Void
    let release: (ComputerUseStopping) -> Void
    let acquireLease: (String) async throws -> Void
    let releaseLease: () async -> Void
    let prepare: (AgentDesktopPreference) async throws -> PreparedAgentDesktop
    let probe: (
        PreparedAgentDesktop,
        @escaping @Sendable (String?, String?) async throws -> ComputerProbeResult
    ) async throws -> ComputerProbeResult
    let cleanup: (AgentDesktopManifest) async -> CleanupReport
    let releaseDesktop: (PreparedAgentDesktop) async -> Void

    static func live(
        registry: ComputerUseRegistry,
        lease: ComputerUseLease,
        coordinator: AgentDesktopCoordinator,
        sessionToken: String
    ) -> Self {
        Self(
            activate: { candidate in
                await registry.activate(candidate) { previous in
                    await previous.stopComputerUse()
                }
            },
            release: { candidate in registry.release(candidate) },
            acquireLease: { sessionID in try await lease.acquire(sessionID: sessionID) },
            releaseLease: { await lease.release() },
            prepare: { preference in try await coordinator.prepare(
                preference: preference, sessionToken: sessionToken) },
            probe: { prepared, operation in
                try await coordinator.probePreparedWorkspace(prepared) { target, verificationText in
                    try await operation(target, verificationText)
                }
            },
            cleanup: { manifest in await coordinator.cleanup(manifest: manifest) },
            releaseDesktop: { prepared in await coordinator.release(prepared) })
    }
}

@MainActor
@Observable
final class ComputerUseController: ComputerUseStopping {
    private(set) var phase: ComputerUsePhase = .off
    private(set) var isolation: AgentDesktopProviderKind?
    private(set) var cleanupReport: CleanupReport?
    private(set) var safetyMode: ComputerUseSafetyMode = .focusIsolated

    private let sessionID: String
    private let lifecycle: ComputerUseControllerLifecycle
    private let coordinator: AgentDesktopCoordinator?
    private let preference: AgentDesktopPreference
    private var rpc: (any ComputerUseRPC)?
    private var preparedDesktop: PreparedAgentDesktop?
    private var manifest: AgentDesktopManifest?
    private var hostTool: AgentDesktopHostTool?
    private var stopTask: Task<Void, Never>?
    private var watcherTask: Task<Void, Never>?
    private var hasRegistryActivation = false
    private var hasLease = false
    private var isOMPComputerEnabled = false
    private var hasHostTools = false
    private var isComputerToolLive = false

    init(
        sessionID: String = UUID().uuidString,
        registry: ComputerUseRegistry = ComputerUseRegistry(),
        lease: ComputerUseLease = ComputerUseLease(),
        coordinator: AgentDesktopCoordinator = AgentDesktopCoordinator(),
        preference: AgentDesktopPreference = .automatic
    ) {
        self.sessionID = sessionID
        lifecycle = .live(
            registry: registry,
            lease: lease,
            coordinator: coordinator,
            sessionToken: UUID().uuidString)
        self.coordinator = coordinator
        self.preference = preference
        hostTool = AgentDesktopHostTool(coordinator: coordinator)
    }

    init(
        sessionID: String,
        lifecycle: ComputerUseControllerLifecycle,
        preference: AgentDesktopPreference
    ) {
        self.sessionID = sessionID
        self.lifecycle = lifecycle
        coordinator = nil
        self.preference = preference
    }

    func attach(rpc: any ComputerUseRPC, sessionPath: String) {
        self.rpc = rpc
    }

    func attachAndReconcile(rpc: any ComputerUseRPC, sessionPath: String) async {
        attach(rpc: rpc, sessionPath: sessionPath)
        do {
            let state = try await rpc.state()
            if state.enabled {
                _ = try await rpc.setComputerUse(enabled: false, policy: .requireHandoff)
            }
        } catch {
            // An older OMP does not support the lifecycle contract. It remains off.
        }
        phase = .off
    }

    func enable(safetyMode: ComputerUseSafetyMode = .focusIsolated) async {
        guard phase == .off, let rpc else { return }
        self.safetyMode = safetyMode
        phase = .preparing
        do {
            await lifecycle.activate(self)
            hasRegistryActivation = true
            try await lifecycle.acquireLease(sessionID)
            hasLease = true

            let requestedPreference: AgentDesktopPreference = safetyMode == .legacyBestEffort
                ? .backgroundOnly
                : preference
            let prepared = try await lifecycle.prepare(requestedPreference)
            preparedDesktop = prepared
            manifest = AgentDesktopManifest(prepared: prepared)
            isolation = prepared.provider

            var needsHandoff = false
            switch safetyMode {
            case .focusIsolated:
                let state = try await rpc.setComputerUse(enabled: true, policy: .requireHandoff)
                guard state.enabled, state.foregroundPolicy == .requireHandoff else {
                    throw ComputerUseControllerError.ompUnavailable
                }
                isOMPComputerEnabled = true
                try await rpc.setHostTools([AgentDesktopHostTool.definition])
                hasHostTools = true
                let probe = try await lifecycle.probe(prepared) { target, verificationText in
                    try await rpc.probeComputerUse(target: target, verificationText: verificationText)
                }
                guard probe.capabilities.isReady else {
                    throw ComputerUseControllerError.permissionDenied
                }
                needsHandoff = !probe.captureSucceeded || probe.backgroundInputSucceeded != true
            case .legacyBestEffort:
                try await rpc.setLegacyComputerUse(enabled: true)
                isOMPComputerEnabled = true
                try await rpc.setHostTools([AgentDesktopHostTool.definition])
                hasHostTools = true
            }
            phase = needsHandoff
                ? .needsHandoff(
                    target: "Agent Desktop",
                    reason: "Background capture or input is unavailable")
                : .ready
            startManifestWatcher()
        } catch {
            await rollbackEnable()
            phase = .unavailable(
                message: "Computer use could not start",
                isBestEffortAvailable: safetyMode == .focusIsolated
                    && Self.isLegacyBestEffortAvailable(error))
        }
    }

    func stopComputerUse() async {
        if let stopTask {
            await stopTask.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performStop()
        }
        stopTask = task
        await task.value
        stopTask = nil
    }

    func failClosed() async {
        await stopComputerUse()
        phase = .unavailable(
            message: "Computer use stopped to keep this session safe",
            isBestEffortAvailable: false)
    }

    func handlePermissionLoss() async {
        await failClosed()
    }

    func handleHostToolCall(_ call: HostToolCall) async {
        guard let rpc else { return }
        guard call.name == AgentDesktopHostTool.definition.name,
              phase == .ready || isControlling
        else {
            try? await rpc.sendHostToolResult(
                id: call.id,
                result: errorResult("Host tool is unavailable"),
                isError: true)
            return
        }
        guard let preparedDesktop, let manifest, let hostTool else {
            try? await rpc.sendHostToolResult(
                id: call.id,
                result: errorResult("Computer use is unavailable"),
                isError: true)
            return
        }
        let outcome = await hostTool.handle(call, in: preparedDesktop, manifest: manifest)
        self.manifest = outcome.manifest
        try? await rpc.sendHostToolResult(
            id: call.id,
            result: outcome.result,
            isError: outcome.isError)
    }

    func handleHostToolCancel(targetID: String) async {
        await hostTool?.cancel(callID: targetID)
    }

    func handleToolStarted(_ payload: JSONValue) {
        guard payload["toolName"]?.stringValue == "computer", phase == .ready else { return }
        isComputerToolLive = true
        let target = payload["target"]?.stringValue ?? "Agent Desktop"
        phase = .controlling(target: target)
    }

    func handleToolEnded(_ payload: JSONValue) {
        guard payload["toolName"]?.stringValue == "computer" else { return }
        isComputerToolLive = false
        if isControlling { phase = .ready }
    }

    private var isControlling: Bool {
        if case .controlling = phase { return true }
        return false
    }

    private func rollbackEnable() async {
        watcherTask?.cancel()
        watcherTask = nil
        await disableRemoteComputerUse()
        await releaseResources()
    }

    private func performStop() async {
        guard phase != .off else { return }
        phase = .stopping
        defer { phase = .off }
        watcherTask?.cancel()
        watcherTask = nil
        if let rpc {
            if isComputerToolLive {
                try? await rpc.abort()
                await waitForComputerToolToEnd()
            }
        }
        await disableRemoteComputerUse()
        await releaseResources()
    }

    private func releaseResources() async {
        if let manifest {
            cleanupReport = await lifecycle.cleanup(manifest)
            self.manifest = nil
        }
        if let preparedDesktop {
            await lifecycle.releaseDesktop(preparedDesktop)
            self.preparedDesktop = nil
            isolation = nil
        }
        if hasLease {
            await lifecycle.releaseLease()
            hasLease = false
        }
        if hasRegistryActivation {
            lifecycle.release(self)
            hasRegistryActivation = false
        }
        isComputerToolLive = false
    }

    private func disableRemoteComputerUse() async {
        guard let rpc else { return }
        if hasHostTools {
            try? await rpc.setHostTools([])
            hasHostTools = false
        }
        guard isOMPComputerEnabled else { return }
        switch safetyMode {
        case .focusIsolated:
            try? await rpc.setComputerUse(enabled: false, policy: .requireHandoff)
        case .legacyBestEffort:
            try? await rpc.setLegacyComputerUse(enabled: false)
        }
        isOMPComputerEnabled = false
    }

    private func waitForComputerToolToEnd() async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while isComputerToolLive, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func startManifestWatcher() {
        guard let coordinator, let preparedDesktop else { return }
        watcherTask?.cancel()
        watcherTask = Task { [weak self] in
            guard let self,
                  let stream = try? await coordinator.watchWindows(in: preparedDesktop)
            else { return }
            for await event in stream {
                guard !Task.isCancelled else { return }
                self.manifest?.apply(event)
            }
        }
    }

    private func errorResult(_ message: String) -> JSONValue {
        .object([
            "content": .array([
                .object(["type": .string("text"), "text": .string(message)]),
            ]),
        ])
    }

    private static func isLegacyBestEffortAvailable(_ error: any Error) -> Bool {
        guard case let RpcClientError.commandFailed(_, message, _) = error else { return false }
        return message.localizedCaseInsensitiveContains("unknown command")
    }
}

private enum ComputerUseControllerError: Error {
    case ompUnavailable
    case permissionDenied
}
