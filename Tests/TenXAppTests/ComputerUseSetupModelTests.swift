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

private actor FakeSetupOMP: ComputerUseSetupOMP {
    enum Failure: Error { case unknownCommand }

    private(set) var commands: [String] = []
    private(set) var didCreateSessionHistory = false
    private let hasUnknownContract: Bool

    init(failure: Failure? = nil) {
        hasUnknownContract = failure != nil
    }

    func getComputerUse() async throws -> ComputerUseRPCState {
        commands.append("get")
        if hasUnknownContract {
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

    func shutdown() async {
        commands.append("shutdown")
    }
}

private struct FakeSetupProvider: AgentDesktopProvider {
    let kind: AgentDesktopProviderKind
    let result: ProviderProbe

    init(kind: AgentDesktopProviderKind, probe: ProviderAvailability) {
        self.kind = kind
        result = ProviderProbe(availability: probe, integrationVersion: "1.0", capabilities: .background)
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
