import AppKit
import Foundation
import Observation
import OmpKit

enum ComputerUsePreferenceStore {
    static let isolationKey = "computerUse.isolationPreference"

    static func preference(defaults: UserDefaults = .standard) -> AgentDesktopPreference {
        guard let rawValue = defaults.string(forKey: isolationKey),
              let preference = AgentDesktopPreference(rawValue: rawValue)
        else { return .automatic }
        return preference
    }

    static func save(_ preference: AgentDesktopPreference, defaults: UserDefaults = .standard) {
        defaults.set(preference.rawValue, forKey: isolationKey)
    }
}

enum OmpComputerContract: Sendable, Equatable {
    case complete
    case legacyBestEffort
    case unavailable
}

struct ComputerUseReadiness: Sendable, Equatable {
    var ompContract: OmpComputerContract
    var capabilities: ComputerCapabilities
    var preferredProvider: ProviderProbe
    var backgroundFallbackAvailable: Bool
    var providerProbes: [AgentDesktopProviderKind: ProviderProbe]

    static let unavailable = ComputerUseReadiness(
        ompContract: .unavailable,
        capabilities: .unknown,
        preferredProvider: ProviderProbe(
            availability: .missing,
            integrationVersion: nil,
            capabilities: .background),
        backgroundFallbackAvailable: false,
        providerProbes: [:])
}

enum ComputerUseTestOutcome: Sendable, Equatable {
    case passed
    case failed
    case cancelled
}

struct ComputerUseProbeReport: Sendable, Equatable {
    let outcome: ComputerUseTestOutcome
    let capabilities: ComputerCapabilities
    let captureSucceeded: Bool
    let backgroundInputSucceeded: Bool?
    let helperAvailable: Bool
    let windowPlacementSucceeded: Bool?
}

enum DisposableProbeResult: Sendable {
    case success(contract: OmpComputerContract, probe: ComputerProbeResult)
    case failed(contract: OmpComputerContract)
    case cancelled

    var contract: OmpComputerContract {
        switch self {
        case let .success(contract, _), let .failed(contract): contract
        case .cancelled: .unavailable
        }
    }

    var probe: ComputerProbeResult? {
        guard case let .success(_, probe) = self else { return nil }
        return probe
    }
}

enum ComputerUseSetupAction {
    case openScreenRecordingSettings
    case openAccessibilitySettings
    case showAeroSpaceInstructions
    case showHammerspoonInstructions
    case runHarmlessTest
}

protocol ComputerUseSetupOMP: Sendable {
    func getComputerUse() async throws -> ComputerUseRPCState
    func setComputerUse(enabled: Bool, policy: ComputerForegroundPolicy) async throws -> ComputerUseRPCState
    func probeComputerUse(target: String?, verificationText: String?) async throws -> ComputerProbeResult
    /// Returns false while the process still owns the disposable RPC session.
    func shutdown() async -> Bool
}

protocol DisposableComputerUseRPC: AnyObject, Sendable {
    func start() async throws -> ReadyFrame
    func send(_ command: RpcCommand, timeout: Duration?) async throws -> RpcResponse
    func shutdown(deadline: ContinuousClock.Instant?) async -> Bool
    var termination: AsyncStream<Void> { get }
}

extension RpcClient: DisposableComputerUseRPC {}

extension DisposableComputerUseRPC {
    func send(_ command: RpcCommand) async throws -> RpcResponse {
        try await send(command, timeout: nil)
    }
}

actor DisposableComputerUseOMP: ComputerUseSetupOMP {
    private let executable: String
    private let clientFactory: @Sendable (RpcClientConfiguration) -> any DisposableComputerUseRPC
    private var client: (any DisposableComputerUseRPC)?
    private var terminationTask: Task<Void, Never>?

    init(
        executable: String,
        clientFactory: @escaping @Sendable (RpcClientConfiguration) -> any DisposableComputerUseRPC = {
            RpcClient(configuration: $0)
        }
    ) {
        self.executable = executable
        self.clientFactory = clientFactory
    }

    init(client: any DisposableComputerUseRPC) {
        executable = ""
        clientFactory = { _ in client }
        self.client = client
    }

    func getComputerUse() async throws -> ComputerUseRPCState {
        let response = try await rpc().send(.getComputerUse())
        guard let state = ComputerUseRPCState(json: response.data) else {
            throw RpcClientError.startupFailed("computer state was malformed")
        }
        return state
    }

    func setComputerUse(enabled: Bool, policy: ComputerForegroundPolicy) async throws -> ComputerUseRPCState {
        let response = try await rpc().send(.setComputerUse(enabled: enabled, foregroundPolicy: policy))
        guard let state = ComputerUseRPCState(json: response.data) else {
            throw RpcClientError.startupFailed("computer state was malformed")
        }
        return state
    }

    func probeComputerUse(target: String?, verificationText: String?) async throws -> ComputerProbeResult {
        let response = try await rpc().send(.probeComputerUse(target: target, verificationText: verificationText))
        guard let result = ComputerProbeResult(json: response.data) else {
            throw RpcClientError.startupFailed("computer probe was malformed")
        }
        return result
    }

    func shutdown() async -> Bool {
        guard let client else { return true }
        let isTerminated = await client.shutdown(deadline: nil)
        if isTerminated {
            release(client)
        } else {
            observeTermination(of: client)
        }
        return isTerminated
    }

    var hasRetainedClient: Bool { client != nil }

    private func rpc() async throws -> any DisposableComputerUseRPC {
        if let client { return client }
        var configuration = RpcClientConfiguration()
        configuration.executable = executable
        configuration.noSession = true
        let client = clientFactory(configuration)
        try await client.start()
        self.client = client
        return client
    }

    private func observeTermination(of client: any DisposableComputerUseRPC) {
        guard terminationTask == nil else { return }
        terminationTask = Task { [weak self] in
            for await _ in client.termination {
                await self?.confirmGroupTermination(of: client)
                return
            }
        }
    }

    private func confirmGroupTermination(of terminatingClient: any DisposableComputerUseRPC) async {
        guard client === terminatingClient else { return }
        while client === terminatingClient {
            if await terminatingClient.shutdown(deadline: ContinuousClock.now.advanced(by: .seconds(1))) {
                release(terminatingClient)
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func release(_ terminatedClient: any DisposableComputerUseRPC) {
        guard client === terminatedClient else { return }
        client = nil
        terminationTask = nil
    }
}

@MainActor
@Observable
final class ComputerUseSetupModel {
    private(set) var readiness: ComputerUseReadiness
    private(set) var harmlessTest: ComputerUseProbeReport?
    private(set) var isChecking = false
    private(set) var instructions: String?
    private(set) var ompVersion: String
    private let automaticallyChecksReadiness: Bool
    var preference: AgentDesktopPreference {
        didSet { ComputerUsePreferenceStore.save(preference, defaults: defaults) }
    }

    @ObservationIgnored private let omp: any ComputerUseSetupOMP
    @ObservationIgnored private let providers: [AgentDesktopProviderKind: any AgentDesktopProvider]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var cleanupTask: Task<Void, Never>?

    init(
        omp: any ComputerUseSetupOMP = DisposableComputerUseOMP(executable: "omp"),
        providers: [any AgentDesktopProvider] = [AeroSpaceProvider(), HammerspoonProvider(), BackgroundProvider()],
        preference: AgentDesktopPreference? = nil,
        readiness: ComputerUseReadiness = .unavailable,
        harmlessTest: ComputerUseProbeReport? = nil,
        ompVersion: String = "Unavailable",
        automaticallyChecksReadiness: Bool = true,
        defaults: UserDefaults = .standard
    ) {
        self.omp = omp
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.kind, $0) })
        self.defaults = defaults
        self.preference = preference ?? ComputerUsePreferenceStore.preference(defaults: defaults)
        self.readiness = readiness
        self.harmlessTest = harmlessTest
        self.ompVersion = ompVersion
        self.automaticallyChecksReadiness = automaticallyChecksReadiness
    }

    var shouldAutomaticallyCheckReadiness: Bool { automaticallyChecksReadiness }

    func runReadinessCheck() async {
        guard !isChecking else { return }
        isChecking = true
        let probes = await providerProbes()
        let result = await runDisposableProbe(target: nil, verificationText: nil)
        readiness = ComputerUseReadiness(
            ompContract: result.contract,
            capabilities: result.probe?.capabilities ?? .unknown,
            preferredProvider: preferredProbe(from: probes),
            backgroundFallbackAvailable: probes[.background]?.availability == .healthy,
            providerProbes: probes)
        isChecking = false
    }

    func perform(_ action: ComputerUseSetupAction) async {
        switch action {
        case .openScreenRecordingSettings:
            open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        case .openAccessibilitySettings:
            open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .showAeroSpaceInstructions:
            instructions = "Install AeroSpace separately:\nbrew install nikitabobko/tap/aerospace"
        case .showHammerspoonInstructions:
            instructions = "Add the 10x integration to Hammerspoon separately:\ntenx = require(\"tenx\")"
        case .runHarmlessTest:
            await runHarmlessTest()
        }
    }

    func runHarmlessTest() async {
        guard !isChecking else { return }
        isChecking = true
        let probes = await providerProbes()
        let selected = selectedProvider(from: probes)
        let helperAvailable = selected?.probe.availability == .healthy
        let window = AgentDesktopProbeWindow()
        var prepared: PreparedAgentDesktop?
        var originalWorkspaceID: String?
        var target: AgentDesktopProbeWindow.Target?
        do {
            if let selected {
                prepared = try await selected.provider.prepare(sessionToken: UUID().uuidString.replacingOccurrences(of: "-", with: ""))
            }
            let opened = try window.open()
            target = opened
            if let selected,
               let workspaceID = prepared?.workspaceID {
                originalWorkspaceID = try await selected.provider.listWindows()
                    .first(where: { $0.id == opened.windowID })?.workspaceID
                try await selected.provider.move(windowID: opened.windowID, to: workspaceID)
            }
            let result = await runDisposableProbe(target: opened.windowID, verificationText: opened.verificationText)
            switch result {
            case let .success(contract, probe):
                harmlessTest = ComputerUseProbeReport(
                    outcome: probe.captureSucceeded && probe.backgroundInputSucceeded == true
                        && probe.capabilities.accessibility == .granted && helperAvailable ? .passed : .failed,
                    capabilities: probe.capabilities,
                    captureSucceeded: probe.captureSucceeded,
                    backgroundInputSucceeded: probe.backgroundInputSucceeded,
                    helperAvailable: helperAvailable,
                    windowPlacementSucceeded: prepared?.workspaceID == nil ? nil : true)
                readiness = ComputerUseReadiness(
                    ompContract: contract,
                    capabilities: probe.capabilities,
                    preferredProvider: preferredProbe(from: probes),
                    backgroundFallbackAvailable: probes[.background]?.availability == .healthy,
                    providerProbes: probes)
            case let .failed(contract):
                harmlessTest = failedProbeReport(outcome: .failed, target: target)
                readiness = ComputerUseReadiness(
                    ompContract: contract,
                    capabilities: .unknown,
                    preferredProvider: preferredProbe(from: probes),
                    backgroundFallbackAvailable: probes[.background]?.availability == .healthy,
                    providerProbes: probes)
            case .cancelled:
                harmlessTest = failedProbeReport(outcome: .cancelled, target: target)
            }
        } catch {
            harmlessTest = failedProbeReport(
                outcome: error is CancellationError ? .cancelled : .failed,
                target: target)
        }
        if let selected, let target, let originalWorkspaceID {
            try? await selected.provider.restore(windowID: target.windowID, to: originalWorkspaceID)
        }
        if let prepared, let selected { await selected.provider.release(workspaceID: prepared.workspaceID ?? "") }
        window.close()
        isChecking = false
    }

    private func providerProbes() async -> [AgentDesktopProviderKind: ProviderProbe] {
        var results: [AgentDesktopProviderKind: ProviderProbe] = [:]
        for (kind, provider) in providers {
            results[kind] = await provider.probe()
        }
        return results
    }

    private func preferredProbe(from probes: [AgentDesktopProviderKind: ProviderProbe]) -> ProviderProbe {
        let candidates: [AgentDesktopProviderKind] = switch preference {
        case .automatic: [.aeroSpace, .hammerspoon, .background]
        case .aeroSpace: [.aeroSpace]
        case .hammerspoon: [.hammerspoon]
        case .backgroundOnly: [.background]
        }
        if preference == .automatic {
            for kind in candidates where probes[kind]?.availability == .healthy {
                return probes[kind]!
            }
        }
        for kind in candidates where probes[kind] != nil { return probes[kind]! }
        return ComputerUseReadiness.unavailable.preferredProvider
    }

    private func selectedProvider(
        from probes: [AgentDesktopProviderKind: ProviderProbe]
    ) -> (provider: any AgentDesktopProvider, probe: ProviderProbe)? {
        let candidates: [AgentDesktopProviderKind] = switch preference {
        case .automatic: [.aeroSpace, .hammerspoon, .background]
        case .aeroSpace: [.aeroSpace]
        case .hammerspoon: [.hammerspoon]
        case .backgroundOnly: [.background]
        }
        for kind in candidates {
            if let provider = providers[kind], let probe = probes[kind], probe.availability == .healthy {
                return (provider, probe)
            }
        }
        return nil
    }

    func runDisposableProbe(
        target: String?,
        verificationText: String?
    ) async -> DisposableProbeResult {
        var didAttemptEnable = false
        do {
            _ = try await omp.getComputerUse()
            didAttemptEnable = true
            let enabled = try await omp.setComputerUse(enabled: true, policy: .requireHandoff)
            guard enabled.enabled, enabled.foregroundPolicy == .requireHandoff else {
                await settleDisposableCleanup(requiresDisable: true)
                return .failed(contract: .unavailable)
            }
            let probe = try await omp.probeComputerUse(target: target, verificationText: verificationText)
            let disabled = try await omp.setComputerUse(enabled: false, policy: .requireHandoff)
            await settleDisposableCleanup(requiresDisable: false)
            guard !disabled.enabled else { return .failed(contract: .unavailable) }
            return .success(contract: .complete, probe: probe)
        } catch {
            await settleDisposableCleanup(requiresDisable: didAttemptEnable)
            if error is CancellationError { return .cancelled }
            return .failed(contract: isUnknownComputerCommand(error) ? .legacyBestEffort : .unavailable)
        }
    }

    private func settleDisposableCleanup(requiresDisable: Bool) async {
        if let cleanupTask {
            await cleanupTask.value
            return
        }
        let omp = omp
        let task = Task {
            if requiresDisable {
                _ = try? await omp.setComputerUse(enabled: false, policy: .requireHandoff)
            }
            while !(await omp.shutdown()) {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        cleanupTask = task
        await task.value
        cleanupTask = nil
    }

    private func isUnknownComputerCommand(_ error: any Error) -> Bool {
        guard case let RpcClientError.commandFailed(_, message, _) = error else {
            return String(describing: error).localizedCaseInsensitiveContains("unknown command")
        }
        return message.localizedCaseInsensitiveContains("unknown command")
    }

    private func failedProbeReport(
        outcome: ComputerUseTestOutcome,
        target: AgentDesktopProbeWindow.Target?
    ) -> ComputerUseProbeReport {
        ComputerUseProbeReport(
            outcome: outcome,
            capabilities: .unknown,
            captureSucceeded: false,
            backgroundInputSucceeded: false,
            helperAvailable: false,
            windowPlacementSucceeded: target == nil ? nil : false)
    }

    private func open(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }
}
