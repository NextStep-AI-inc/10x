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

actor DisposableComputerUseOMP: ComputerUseSetupOMP {
    private let executable: String
    private var client: RpcClient?
    private var terminationTask: Task<Void, Never>?

    init(executable: String) {
        self.executable = executable
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
        let isTerminated = await client.shutdown()
        if isTerminated {
            self.client = nil
            terminationTask?.cancel()
            terminationTask = nil
        } else {
            observeTermination(of: client)
        }
        return isTerminated
    }

    private func rpc() async throws -> RpcClient {
        if let client { return client }
        var configuration = RpcClientConfiguration()
        configuration.executable = executable
        configuration.noSession = true
        let client = RpcClient(configuration: configuration)
        try await client.start()
        self.client = client
        return client
    }

    private func observeTermination(of client: RpcClient) {
        guard terminationTask == nil else { return }
        terminationTask = Task { [weak self] in
            for await _ in client.termination {
                await self?.releaseTerminatedClient(client)
                return
            }
        }
    }

    private func releaseTerminatedClient(_ terminatedClient: RpcClient) {
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
            if let probe = result.probe {
                harmlessTest = ComputerUseProbeReport(
                    outcome: probe.captureSucceeded && probe.backgroundInputSucceeded != false
                        && probe.capabilities.accessibility == .granted ? .passed : .failed,
                    capabilities: probe.capabilities,
                    captureSucceeded: probe.captureSucceeded,
                    backgroundInputSucceeded: probe.backgroundInputSucceeded,
                    helperAvailable: helperAvailable,
                    windowPlacementSucceeded: prepared?.workspaceID == nil ? nil : true)
                readiness = ComputerUseReadiness(
                    ompContract: result.contract,
                    capabilities: probe.capabilities,
                    preferredProvider: preferredProbe(from: probes),
                    backgroundFallbackAvailable: probes[.background]?.availability == .healthy,
                    providerProbes: probes)
            }
        } catch {
            harmlessTest = ComputerUseProbeReport(
                outcome: error is CancellationError ? .cancelled : .failed,
                capabilities: .unknown,
                captureSucceeded: false,
                backgroundInputSucceeded: nil,
                helperAvailable: false,
                windowPlacementSucceeded: target == nil ? nil : false)
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

    private func runDisposableProbe(
        target: String?,
        verificationText: String?
    ) async -> (contract: OmpComputerContract, probe: ComputerProbeResult?) {
        var didAttemptEnable = false
        do {
            _ = try await omp.getComputerUse()
            didAttemptEnable = true
            let enabled = try await omp.setComputerUse(enabled: true, policy: .requireHandoff)
            guard enabled.enabled, enabled.foregroundPolicy == .requireHandoff else {
                await settleDisposableCleanup(requiresDisable: true)
                return (.unavailable, nil)
            }
            let probe = try await omp.probeComputerUse(target: target, verificationText: verificationText)
            let disabled = try await omp.setComputerUse(enabled: false, policy: .requireHandoff)
            await settleDisposableCleanup(requiresDisable: false)
            guard !disabled.enabled else { return (.unavailable, probe) }
            return (.complete, probe)
        } catch {
            await settleDisposableCleanup(requiresDisable: didAttemptEnable)
            return (isUnknownComputerCommand(error) ? .legacyBestEffort : .unavailable, nil)
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
                try? await Task.sleep(for: .milliseconds(10))
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

    private func open(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }
}
