import OmpKit
import Testing
@testable import TenXApp

@MainActor @Test func setupProbeUsesDisposableOMPAndNeverPersistsEnablement() async {
    let omp = FakeSetupOMP()
    let model = ComputerUseSetupModel(
        omp: omp,
        providers: [FakeSetupProvider(kind: .background, probe: .healthy)])

    await model.runReadinessCheck()

    #expect(await omp.commands == ["get", "enable", "probe", "disable", "shutdown"])
    #expect(model.readiness.ompContract == .complete)
    #expect(await omp.didCreateSessionHistory == false)
}

@MainActor @Test func unknownComputerContractLeavesDisposableProcessDisabled() async {
    let omp = FakeSetupOMP(failure: .unknownCommand)
    let model = ComputerUseSetupModel(
        omp: omp,
        providers: [FakeSetupProvider(kind: .background, probe: .healthy)])

    await model.runReadinessCheck()

    #expect(model.readiness.ompContract == .legacyBestEffort)
    #expect(await omp.commands == ["get", "shutdown"])
}

@MainActor @Test func failedProbeRetriesConfirmedShutdownAfterDisabling() async {
    let omp = FakeSetupOMP(failure: .probe, shutdownResults: [false, true])
    let model = ComputerUseSetupModel(
        omp: omp,
        providers: [FakeSetupProvider(kind: .background, probe: .healthy)])

    await model.runReadinessCheck()

    #expect(await omp.commands == ["get", "enable", "probe", "disable", "shutdown", "shutdown"])
    #expect(model.readiness.ompContract == .unavailable)
}

@MainActor @Test func automaticPreferenceReportsTheFirstHealthyHelper() async {
    let omp = FakeSetupOMP()
    let model = ComputerUseSetupModel(
        omp: omp,
        providers: [
            FakeSetupProvider(kind: .aeroSpace, probe: .missing),
            FakeSetupProvider(kind: .hammerspoon, probe: .healthy),
            FakeSetupProvider(kind: .background, probe: .healthy),
        ],
        preference: .automatic)

    await model.runReadinessCheck()

    #expect(model.readiness.preferredProvider.integrationVersion == "hammerspoon")
}

private actor FakeSetupOMP: ComputerUseSetupOMP {
    enum Failure: Error { case unknownCommand, probe }

    private(set) var commands: [String] = []
    private(set) var didCreateSessionHistory = false
    private let failure: Failure?
    private var shutdownResults: [Bool]

    init(failure: Failure? = nil, shutdownResults: [Bool] = [true]) {
        self.failure = failure
        self.shutdownResults = shutdownResults
    }

    func getComputerUse() async throws -> ComputerUseRPCState {
        commands.append("get")
        if failure == .unknownCommand {
            throw RpcClientError.commandFailed(command: "get_computer_use", error: "unknown command", code: nil)
        }
        return ComputerUseRPCState(enabled: false, foregroundPolicy: .requireHandoff)
    }

    func setComputerUse(enabled: Bool, policy: ComputerForegroundPolicy) async throws -> ComputerUseRPCState {
        commands.append(enabled ? "enable" : "disable")
        return ComputerUseRPCState(enabled: enabled, foregroundPolicy: policy)
    }

    func probeComputerUse(target: String?, verificationText: String?) async throws -> ComputerProbeResult {
        commands.append("probe")
        if failure == .probe { throw Failure.probe }
        return ComputerProbeResult(json: .object([
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

    func shutdown() async -> Bool {
        commands.append("shutdown")
        return shutdownResults.isEmpty ? true : shutdownResults.removeFirst()
    }
}

private struct FakeSetupProvider: AgentDesktopProvider {
    let kind: AgentDesktopProviderKind
    let result: ProviderProbe

    init(kind: AgentDesktopProviderKind, probe: ProviderAvailability) {
        self.kind = kind
        result = ProviderProbe(availability: probe, integrationVersion: kind.rawValue, capabilities: .background)
    }

    func probe() async -> ProviderProbe { result }
    func prepare(sessionToken: String) async throws -> PreparedAgentDesktop {
        PreparedAgentDesktop(provider: kind, workspaceID: nil, capabilities: result.capabilities)
    }
    func listWindows() async throws -> [AgentWindow] { [] }
    func watchWindows() async throws -> AsyncStream<AgentWindowEvent> { AsyncStream { $0.finish() } }
    func move(windowID: String, to workspaceID: String) async throws {}
    func restore(windowID: String, to workspaceID: String) async throws {}
    func openVisibly(workspaceID: String) async throws {}
    func release(workspaceID: String) async {}
}
