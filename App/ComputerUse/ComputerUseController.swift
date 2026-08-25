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
    let probe: (PreparedAgentDesktop, @escaping @Sendable (String?, String?) async throws -> ComputerProbeResult) async throws -> ComputerProbeResult
    let cleanup: (AgentDesktopManifest) async -> CleanupReport
    let releaseDesktop: (PreparedAgentDesktop) async -> Void

    init(
        activate: @escaping (ComputerUseStopping) async -> Void,
        release: @escaping (ComputerUseStopping) -> Void,
        acquireLease: @escaping (String) async throws -> Void,
        releaseLease: @escaping () async -> Void,
        prepare: @escaping (AgentDesktopPreference) async throws -> PreparedAgentDesktop,
        probe: @escaping (PreparedAgentDesktop, @escaping @Sendable (String?, String?) async throws -> ComputerProbeResult) async throws -> ComputerProbeResult,
        cleanup: @escaping (AgentDesktopManifest) async -> CleanupReport,
        releaseDesktop: @escaping (PreparedAgentDesktop) async -> Void
    ) {
        self.activate = activate
        self.release = release
        self.acquireLease = acquireLease
        self.releaseLease = releaseLease
        self.prepare = prepare
        self.probe = probe
        self.cleanup = cleanup
        self.releaseDesktop = releaseDesktop
    }

    static func live(registry: ComputerUseRegistry, lease: ComputerUseLease, coordinator: AgentDesktopCoordinator, sessionToken: String) -> Self {
        Self(
            activate: { candidate in await registry.activate(candidate) { await $0.stopComputerUse() } },
            release: { registry.release($0) },
            acquireLease: { try await lease.acquire(sessionID: $0) },
            releaseLease: { await lease.release() },
            prepare: { try await coordinator.prepare(preference: $0, sessionToken: sessionToken) },
            probe: { prepared, operation in
                try await coordinator.probePreparedWorkspace(prepared) { try await operation($0, $1) }
            },
            cleanup: { await coordinator.cleanup(manifest: $0) },
            releaseDesktop: { await coordinator.release($0) })
    }
}

@MainActor
@Observable
final class ComputerUseController: ComputerUseStopping {
    private static let stopLimit: Duration = .seconds(2)

    private(set) var phase: ComputerUsePhase = .off
    private(set) var isolation: AgentDesktopProviderKind?
    private(set) var cleanupReport: CleanupReport?
    private(set) var safetyMode: ComputerUseSafetyMode = .focusIsolated
    private(set) var isAwaitingConfirmedProcessExit = false

    private let sessionID: String
    private let lifecycle: ComputerUseControllerLifecycle
    private let coordinator: AgentDesktopCoordinator?
    private let preference: AgentDesktopPreference
    private let cancellationBag = TaskCancellationBag()
    private var rpc: (any ComputerUseRPC)?
    private var terminateProcess: (@Sendable (ContinuousClock.Instant) async -> Bool)?
    private var preparedDesktop: PreparedAgentDesktop?
    private var manifest: AgentDesktopManifest?
    private var hostTool: AgentDesktopHostTool?
    private var stopTask: Task<Void, Never>?
    private var watcherTask: Task<Void, Never>?
    private var hostCalls: [String: Task<Void, Never>] = [:]
    private var remoteMutations: [UUID: Task<Void, Never>] = [:]
    /// Retained after a bounded Stop returns so leases are not released early.
    private var resourceCleanupTask: Task<Void, Never>?
    private var hostResultsSent: Set<String> = []
    private var cancelledHostCallIDs: Set<String> = []
    private var lifecycleGeneration = 0
    private var hasRegistryActivation = false
    private var hasLease = false
    /// Set before an RPC starts: a timeout is an indeterminate remote mutation.
    private var computerMutationAttempted = false
    private var hostToolsMutationAttempted = false
    private var isComputerToolLive = false

    init(sessionID: String = UUID().uuidString, registry: ComputerUseRegistry = ComputerUseRegistry(), lease: ComputerUseLease = ComputerUseLease(), coordinator: AgentDesktopCoordinator = AgentDesktopCoordinator(), preference: AgentDesktopPreference = .automatic) {
        self.sessionID = sessionID
        lifecycle = .live(registry: registry, lease: lease, coordinator: coordinator, sessionToken: UUID().uuidString)
        self.coordinator = coordinator
        self.preference = preference
        hostTool = AgentDesktopHostTool(coordinator: coordinator)
    }

    init(sessionID: String, lifecycle: ComputerUseControllerLifecycle, preference: AgentDesktopPreference) {
        self.sessionID = sessionID
        self.lifecycle = lifecycle
        coordinator = nil
        self.preference = preference
    }

    func attach(rpc: any ComputerUseRPC, sessionPath: String, terminateProcess: @escaping @Sendable (ContinuousClock.Instant) async -> Bool = { _ in false }) {
        self.rpc = rpc
        self.terminateProcess = terminateProcess
        isAwaitingConfirmedProcessExit = false
    }

    func attachAndReconcile(rpc: any ComputerUseRPC, sessionPath: String, terminateProcess: @escaping @Sendable (ContinuousClock.Instant) async -> Bool = { _ in false }) async {
        attach(rpc: rpc, sessionPath: sessionPath, terminateProcess: terminateProcess)
        let deadline = ContinuousClock.now.advanced(by: Self.stopLimit)
        do {
            let state = try await bounded(deadline: deadline) { try await rpc.state() }
            guard state.enabled else { phase = .off; return }
            computerMutationAttempted = true
            if await disableRemoteComputerUse(deadline: deadline) { phase = .off }
            else { _ = await terminateAndRelease(deadline: deadline); phase = unavailablePhase() }
        } catch {
            guard Self.isUnknownComputerCommand(error) else {
                _ = await terminateAndRelease(deadline: deadline); phase = unavailablePhase(); return
            }
            safetyMode = .legacyBestEffort
            computerMutationAttempted = true
            if await disableRemoteComputerUse(deadline: deadline) { phase = .off }
            else { _ = await terminateAndRelease(deadline: deadline); phase = unavailablePhase() }
        }
    }

    func enable(safetyMode: ComputerUseSafetyMode = .focusIsolated) async {
        guard phase == .off, let rpc else { return }
        self.safetyMode = safetyMode
        phase = .preparing
        let operation = lifecycleGeneration
        do {
            await lifecycle.activate(self)
            hasRegistryActivation = true
            guard isCurrentEnable(operation) else { await releaseResources(); return }
            try await lifecycle.acquireLease(sessionID)
            hasLease = true
            guard isCurrentEnable(operation) else { await releaseResources(); return }
            let requestedPreference: AgentDesktopPreference = safetyMode == .legacyBestEffort ? .backgroundOnly : preference
            let prepared = try await lifecycle.prepare(requestedPreference)
            guard isCurrentEnable(operation) else {
                await lifecycle.releaseDesktop(prepared)
                await releaseResources()
                return
            }
            guard safetyMode == .legacyBestEffort || prepared.capabilities.canIsolate else {
                throw ComputerUseControllerError.isolationUnavailable
            }
            preparedDesktop = prepared
            manifest = AgentDesktopManifest(prepared: prepared)
            isolation = prepared.provider

            var needsHandoff = false
            switch safetyMode {
            case .focusIsolated:
                computerMutationAttempted = true
                let state = try await runRemoteMutation {
                    try await rpc.setComputerUse(enabled: true, policy: .requireHandoff)
                }
                guard isCurrentEnable(operation) else { return }
                guard state.enabled, state.foregroundPolicy == .requireHandoff else { throw ComputerUseControllerError.ompUnavailable }
                try await requireAvailableComputer(rpc)
                guard isCurrentEnable(operation) else { return }
                hostToolsMutationAttempted = true
                try await runRemoteMutation {
                    try await rpc.setHostTools([AgentDesktopHostTool.definition])
                }
                guard isCurrentEnable(operation) else { return }
                let probe = try await lifecycle.probe(prepared) { try await rpc.probeComputerUse(target: $0, verificationText: $1) }
                guard isCurrentEnable(operation) else { return }
                guard probe.capabilities.isReady else { throw ComputerUseControllerError.permissionDenied }
                needsHandoff = !probe.captureSucceeded || probe.backgroundInputSucceeded != true
            case .legacyBestEffort:
                computerMutationAttempted = true
                try await runRemoteMutation { try await rpc.setLegacyComputerUse(enabled: true) }
                guard isCurrentEnable(operation) else { return }
                try await requireAvailableModel(rpc, requiresEnabledComputerState: false)
                guard isCurrentEnable(operation) else { return }
                hostToolsMutationAttempted = true
                try await runRemoteMutation {
                    try await rpc.setHostTools([AgentDesktopHostTool.definition])
                }
                guard isCurrentEnable(operation) else { return }
            }
            guard isCurrentEnable(operation) else { return }
            phase = needsHandoff ? .needsHandoff(target: "Agent Desktop", reason: "Background capture or input is unavailable") : .ready
            startManifestWatcher()
        } catch {
            guard isCurrentEnable(operation) else { return }
            let stopped = await rollbackEnable()
            phase = stopped
                ? .unavailable(message: "Computer use could not start", isBestEffortAvailable: safetyMode == .focusIsolated && Self.isLegacyBestEffortAvailable(error))
                : unavailablePhase()
        }
    }

    func stopComputerUse() async {
        if let stopTask { await stopTask.value; return }
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
        phase = unavailablePhase()
    }

    func handleProcessTerminated() async {
        guard computerMutationAttempted || hostToolsMutationAttempted || hasLease
              || hasRegistryActivation || preparedDesktop != nil || manifest != nil
              || resourceCleanupTask != nil
        else { return }
        lifecycleGeneration += 1
        isAwaitingConfirmedProcessExit = false
        watcherTask?.cancel()
        watcherTask = nil
        _ = await cancelAndSettleHostCalls(deadline: ContinuousClock.now.advanced(by: Self.stopLimit))
        computerMutationAttempted = false
        hostToolsMutationAttempted = false
        await releaseResources()
        phase = unavailablePhase()
    }

    func handlePermissionLoss() async { await failClosed() }

    /// The event stream never awaits a launch: cancellation can be consumed immediately.
    func handleHostToolCall(_ call: HostToolCall) {
        guard call.name == AgentDesktopHostTool.definition.name else { sendHostErrorOnce(call.id, message: "Unknown host tool"); return }
        guard !cancelledHostCallIDs.contains(call.id) else {
            sendHostErrorOnce(call.id, message: "Launch cancelled")
            return
        }
        guard phase == .ready || isControlling, let preparedDesktop, let manifest, let hostTool else {
            sendHostErrorOnce(call.id, message: "Computer use is unavailable"); return
        }
        guard hostCalls[call.id] == nil, !hostResultsSent.contains(call.id) else { return }
        let generation = lifecycleGeneration
        let task = Task { @MainActor [weak self, hostTool] in
            let outcome = await withTaskCancellationHandler {
                await hostTool.handle(call, in: preparedDesktop, manifest: manifest)
            } onCancel: {
                Task { await hostTool.cancel(callID: call.id) }
            }
            await self?.finishHostCall(call.id, outcome: outcome, generation: generation)
        }
        hostCalls[call.id] = task
        cancellationBag.insert(task)
    }

    func handleHostToolCancel(targetID: String) {
        cancelledHostCallIDs.insert(targetID)
        let hasLiveCall = hostCalls[targetID] != nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.hostTool?.cancel(callID: targetID)
            guard hasLiveCall else { return }
            self.hostCalls[targetID]?.cancel()
            await self.sendHostErrorOnce(targetID, message: "Launch cancelled", deadline: nil)
        }
    }

    func handleToolStarted(_ payload: JSONValue) {
        guard payload["toolName"]?.stringValue == "computer", phase == .ready else { return }
        isComputerToolLive = true
        phase = .controlling(target: payload["target"]?.stringValue ?? "Agent Desktop")
    }

    func handleToolEnded(_ payload: JSONValue) {
        guard payload["toolName"]?.stringValue == "computer" else { return }
        isComputerToolLive = false
        if isControlling { phase = .ready }
    }

    func refreshAvailability() async {
        guard isLocallyEnabled, let rpc else { return }
        let operation = lifecycleGeneration
        do {
            switch safetyMode {
            case .focusIsolated:
                try await requireAvailableComputer(rpc)
                guard isCurrentEnabledOperation(operation) else { return }
                computerMutationAttempted = true
                let state = try await runRemoteMutation {
                    try await rpc.setComputerUse(enabled: true, policy: .requireHandoff)
                }
                guard isCurrentEnabledOperation(operation), state.enabled,
                      state.foregroundPolicy == .requireHandoff
                else { throw ComputerUseControllerError.ompUnavailable }
            case .legacyBestEffort:
                // Legacy prompt mode cannot authoritatively prove model support.
                throw ComputerUseControllerError.ompUnavailable
            }
        } catch {
            guard isCurrentEnabledOperation(operation) else { return }
            await failClosed()
        }
    }

    private var isLocallyEnabled: Bool {
        switch phase {
        case .preparing, .ready, .controlling, .needsHandoff, .stopping: true
        case .off, .unavailable: false
        }
    }

    private var isControlling: Bool { if case .controlling = phase { true } else { false } }

    private func isCurrentEnable(_ operation: Int) -> Bool {
        operation == lifecycleGeneration && phase == .preparing
    }

    private func isCurrentEnabledOperation(_ operation: Int) -> Bool {
        operation == lifecycleGeneration && isLocallyEnabled
    }

    private func rollbackEnable() async -> Bool {
        lifecycleGeneration += 1
        watcherTask?.cancel()
        watcherTask = nil
        let deadline = ContinuousClock.now.advanced(by: Self.stopLimit)
        let stopped = await disableRemoteComputerUse(deadline: deadline)
        if stopped { return await releaseResources(deadline: deadline) }
        return await terminateAndRelease(deadline: deadline)
    }

    private func performStop() async {
        guard phase != .off else { return }
        phase = .stopping
        lifecycleGeneration += 1
        watcherTask?.cancel()
        watcherTask = nil
        let deadline = ContinuousClock.now.advanced(by: Self.stopLimit)
        guard await settleRemoteMutations(deadline: deadline) else {
            _ = await terminateAndRelease(deadline: deadline)
            phase = unavailablePhase()
            return
        }
        let hostsSettled = await cancelAndSettleHostCalls(deadline: deadline)
        let callStopped = await abortAndWaitForComputerTool(deadline: deadline)
        let remoteStopped: Bool
        if hostsSettled && callStopped {
            remoteStopped = await disableRemoteComputerUse(deadline: deadline)
        } else {
            remoteStopped = false
        }
        if remoteStopped {
            if await releaseResources(deadline: deadline) { phase = .off }
            else { phase = unavailablePhase() }
        } else {
            _ = await terminateAndRelease(deadline: deadline)
            phase = unavailablePhase()
        }
    }

    private func cancelAndSettleHostCalls(deadline: ContinuousClock.Instant) async -> Bool {
        let ids = Array(hostCalls.keys)
        for id in ids {
            await hostTool?.cancel(callID: id)
            hostCalls[id]?.cancel()
            await sendHostErrorOnce(id, message: "Launch cancelled", deadline: deadline)
        }
        for id in ids {
            guard let task = hostCalls[id] else { continue }
            do { try await bounded(deadline: deadline) { await task.value } }
            catch { return false }
        }
        return true
    }

    private func abortAndWaitForComputerTool(deadline: ContinuousClock.Instant) async -> Bool {
        guard isComputerToolLive else { return true }
        guard let rpc else { return false }
        do { try await bounded(deadline: deadline) { try await rpc.abort() } }
        catch { return false }
        while isComputerToolLive {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return true
    }

    /// Successful acknowledgements are the only way journal flags are cleared.
    private func disableRemoteComputerUse(deadline: ContinuousClock.Instant) async -> Bool {
        guard let rpc else { return !computerMutationAttempted && !hostToolsMutationAttempted }
        var safe = true
        if hostToolsMutationAttempted {
            do {
                try await bounded(deadline: deadline) {
                    try await self.runRemoteMutation { try await rpc.setHostTools([]) }
                }
                hostToolsMutationAttempted = false
            }
            catch { safe = false }
        }
        if computerMutationAttempted {
            do {
                switch safetyMode {
                case .focusIsolated:
                    let state = try await bounded(deadline: deadline) {
                        try await self.runRemoteMutation {
                            try await rpc.setComputerUse(enabled: false, policy: .requireHandoff)
                        }
                    }
                    guard !state.enabled, state.foregroundPolicy == .requireHandoff else { throw ComputerUseControllerError.ompUnavailable }
                case .legacyBestEffort:
                    try await bounded(deadline: deadline) {
                        try await self.runRemoteMutation { try await rpc.setLegacyComputerUse(enabled: false) }
                    }
                }
                computerMutationAttempted = false
            } catch { safe = false }
        }
        return safe && !computerMutationAttempted && !hostToolsMutationAttempted
    }

    private func terminateAndRelease(deadline: ContinuousClock.Instant) async -> Bool {
        guard let terminateProcess,
              await terminateProcess(deadline)
        else {
            isAwaitingConfirmedProcessExit = true
            return false
        }
        isAwaitingConfirmedProcessExit = false
        computerMutationAttempted = false
        hostToolsMutationAttempted = false
        return await releaseResources(deadline: deadline)
    }

    private func runRemoteMutation<T: Sendable>(
        _ operation: @escaping @MainActor () async throws -> T
    ) async throws -> T {
        let id = UUID()
        let stream = AsyncThrowingStream<T, Error>.makeStream()
        let task = Task { @MainActor in
            defer { self.remoteMutations.removeValue(forKey: id) }
            do {
                stream.continuation.yield(try await operation())
                stream.continuation.finish()
            } catch {
                stream.continuation.finish(throwing: error)
            }
        }
        remoteMutations[id] = task
        var iterator = stream.stream.makeAsyncIterator()
        guard let result = try await iterator.next() else {
            throw ComputerUseControllerError.stopTimedOut
        }
        return result
    }

    private func settleRemoteMutations(deadline: ContinuousClock.Instant) async -> Bool {
        while !remoteMutations.isEmpty {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    private func releaseResources(deadline: ContinuousClock.Instant) async -> Bool {
        let task = resourceCleanupTask ?? beginResourceCleanup()
        do {
            try await bounded(deadline: deadline) { await task.value }
            return true
        } catch {
            return false
        }
    }

    private func releaseResources() async {
        await (resourceCleanupTask ?? beginResourceCleanup()).value
    }

    /// Detaches every owned resource before the first suspension so all cleanup
    /// callers, including process-exit handling, can only join this one task.
    private func beginResourceCleanup() -> Task<Void, Never> {
        let ownedManifest = manifest
        manifest = nil
        let ownedDesktop = preparedDesktop
        preparedDesktop = nil
        isolation = nil
        let shouldReleaseLease = hasLease
        hasLease = false
        let shouldReleaseRegistry = hasRegistryActivation
        hasRegistryActivation = false
        isComputerToolLive = false

        let task = Task { @MainActor [self] in
            if let ownedManifest {
                cleanupReport = await lifecycle.cleanup(ownedManifest)
            }
            if let ownedDesktop {
                await lifecycle.releaseDesktop(ownedDesktop)
            }
            if shouldReleaseLease {
                await lifecycle.releaseLease()
            }
            if shouldReleaseRegistry {
                lifecycle.release(self)
            }
            resourceCleanupTask = nil
        }
        resourceCleanupTask = task
        return task
    }

    private func requireAvailableComputer(_ rpc: any ComputerUseRPC) async throws {
        try await requireAvailableModel(rpc, requiresEnabledComputerState: true)
    }

    private func requireAvailableModel(_ rpc: any ComputerUseRPC, requiresEnabledComputerState: Bool) async throws {
        let availability = try await rpc.availability()
        guard availability.hasActiveModel else { throw ComputerUseControllerError.ompUnavailable }
        if requiresEnabledComputerState {
            guard availability.computerUse?.enabled == true, availability.computerUse?.foregroundPolicy == .requireHandoff else { throw ComputerUseControllerError.ompUnavailable }
        } else if let state = availability.computerUse, !state.enabled {
            throw ComputerUseControllerError.ompUnavailable
        }
    }

    private func finishHostCall(_ id: String, outcome: AgentDesktopHostToolOutcome, generation: Int) async {
        hostCalls.removeValue(forKey: id)
        // A cancellation may race a completed launch; retain its claims for cleanup.
        if manifest != nil { manifest = outcome.manifest }
        guard generation == lifecycleGeneration, isLocallyEnabled, !hostResultsSent.contains(id) else { return }
        await sendHostResultOnce(id, result: outcome.result, isError: outcome.isError, deadline: nil)
    }

    private func sendHostErrorOnce(_ id: String, message: String) {
        Task { @MainActor [weak self] in await self?.sendHostErrorOnce(id, message: message, deadline: nil) }
    }

    private func sendHostErrorOnce(_ id: String, message: String, deadline: ContinuousClock.Instant?) async {
        await sendHostResultOnce(id, result: errorResult(message), isError: true, deadline: deadline)
    }

    private func sendHostResultOnce(_ id: String, result: JSONValue, isError: Bool, deadline: ContinuousClock.Instant?) async {
        guard !hostResultsSent.contains(id), let rpc else { return }
        hostResultsSent.insert(id)
        do {
            if let deadline { try await bounded(deadline: deadline) { try await rpc.sendHostToolResult(id: id, result: result, isError: isError) } }
            else { try await rpc.sendHostToolResult(id: id, result: result, isError: isError) }
        } catch {
            // An indeterminate result is handled by the bounded Stop path.
        }
    }

    private func startManifestWatcher() {
        guard let coordinator, let preparedDesktop else { return }
        watcherTask?.cancel()
        watcherTask = Task { [weak self, coordinator, preparedDesktop] in
            guard let stream = try? await coordinator.watchWindows(in: preparedDesktop) else { return }
            for await event in stream {
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in self?.manifest?.apply(event) }
            }
        }
        if let watcherTask { cancellationBag.insert(watcherTask) }
    }

    private func bounded<T: Sendable>(deadline: ContinuousClock.Instant, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let remaining = ContinuousClock.now.duration(to: deadline)
        guard remaining > .zero else { throw ComputerUseControllerError.stopTimedOut }
        let stream = AsyncThrowingStream<T, Error> { continuation in
            Task {
                do {
                    continuation.yield(try await operation())
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            Task {
                do {
                    try await Task.sleep(for: remaining)
                    continuation.finish(throwing: ComputerUseControllerError.stopTimedOut)
                } catch {
                    // The operation completed before the timeout.
                }
            }
        }
        var iterator = stream.makeAsyncIterator()
        guard let value = try await iterator.next() else {
            throw ComputerUseControllerError.stopTimedOut
        }
        return value
    }

    private func errorResult(_ message: String) -> JSONValue {
        .object(["content": .array([.object(["type": .string("text"), "text": .string(message)])])])
    }

    private func unavailablePhase() -> ComputerUsePhase {
        .unavailable(message: "Computer use stopped because its session could not be secured", isBestEffortAvailable: false)
    }

    private static func isLegacyBestEffortAvailable(_ error: any Error) -> Bool { isUnknownComputerCommand(error) }

    private static func isUnknownComputerCommand(_ error: any Error) -> Bool {
        guard case let RpcClientError.commandFailed(_, message, _) = error else { return false }
        return message.localizedCaseInsensitiveContains("unknown command")
    }
}

private enum ComputerUseControllerError: Error {
    case ompUnavailable
    case permissionDenied
    case isolationUnavailable
    case stopTimedOut
}

private final class TaskCancellationBag: @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [Task<Void, Never>] = []

    func insert(_ task: Task<Void, Never>) {
        lock.lock()
        tasks.append(task)
        lock.unlock()
    }

    deinit {
        lock.lock()
        let pending = tasks
        lock.unlock()
        for task in pending { task.cancel() }
    }
}
