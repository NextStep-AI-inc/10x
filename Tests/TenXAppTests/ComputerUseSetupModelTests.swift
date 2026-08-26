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

@MainActor @Test func failedHarmlessProbeReplacesAPriorPassedReport() async throws {
    let omp = FakeSetupOMP(failure: .probe)
    let model = ComputerUseSetupModel(
        omp: omp,
        providers: [FakeSetupProvider(kind: .background, probe: .healthy)],
        harmlessTest: passingReport)

    await model.runHarmlessTest()

    let report = try #require(model.harmlessTest)
    #expect(report.outcome == .failed)
    #expect(report.captureSucceeded == false)
    #expect(report.backgroundInputSucceeded == false)
    #expect(report.helperAvailable == false)
}

@MainActor @Test func cancelledHarmlessProbeReportsCancelledChecks() async throws {
    let omp = FakeSetupOMP(failure: .cancelledProbe)
    let model = ComputerUseSetupModel(
        omp: omp,
        providers: [FakeSetupProvider(kind: .background, probe: .healthy)],
        harmlessTest: passingReport)

    await model.runHarmlessTest()

    let report = try #require(model.harmlessTest)
    #expect(report.outcome == .cancelled)
    #expect(report.captureSucceeded == false)
    #expect(report.backgroundInputSucceeded == false)
    #expect(report.helperAvailable == false)
}

@Test func leaderExitKeepsDisposableRPCOwnedUntilGroupShutdownConfirmsDeath() async {
    let rpc = DetachedDescendantRPC()
    let omp = DisposableComputerUseOMP(client: rpc)

    #expect(await omp.shutdown() == false)
    await rpc.emitLeaderExit()
    await rpc.waitForLeaderExitConfirmationAttempt()
    #expect(await omp.hasRetainedClient)

    await rpc.confirmDescendantExit()
    await rpc.waitForConfirmedShutdown()
    #expect(await omp.hasRetainedClient == false)
    #expect(await rpc.shutdownCalls == 3)
}

private let passingReport = ComputerUseProbeReport(
    outcome: .passed,
    capabilities: ComputerCapabilities(
        backend: "macos",
        capture: .granted,
        input: .granted,
        accessibility: .granted),
    captureSucceeded: true,
    backgroundInputSucceeded: true,
    helperAvailable: true,
    windowPlacementSucceeded: true)

private actor FakeSetupOMP: ComputerUseSetupOMP {
    enum Failure: Error { case unknownCommand, probe, cancelledProbe }

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
        if failure == .cancelledProbe { throw CancellationError() }
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

private actor DetachedDescendantRPC: DisposableComputerUseRPC {
    nonisolated let termination: AsyncStream<Void>
    private let terminationContinuation: AsyncStream<Void>.Continuation
    private var didLeaderExit = false
    private var didDescendantExit = false
    private var leaderExitConfirmation: CheckedContinuation<Void, Never>?
    private var confirmedShutdown: CheckedContinuation<Void, Never>?
    private(set) var shutdownCalls = 0

    init() {
        (termination, terminationContinuation) = AsyncStream.makeStream()
    }

    func start() async throws -> ReadyFrame { ReadyFrame(protocolVersion: 1) }

    func send(_ command: RpcCommand, timeout: Duration?) async throws -> RpcResponse {
        RpcResponse(id: nil, command: command.type, success: false)
    }

    func shutdown(deadline: ContinuousClock.Instant?) async -> Bool {
        shutdownCalls += 1
        if didLeaderExit && !didDescendantExit {
            leaderExitConfirmation?.resume()
            leaderExitConfirmation = nil
            return false
        }
        if didDescendantExit {
            confirmedShutdown?.resume()
            confirmedShutdown = nil
            return true
        }
        return false
    }

    func emitLeaderExit() {
        didLeaderExit = true
        terminationContinuation.yield(())
    }

    func confirmDescendantExit() { didDescendantExit = true }

    func waitForLeaderExitConfirmationAttempt() async {
        if didLeaderExit && shutdownCalls > 1 { return }
        await withCheckedContinuation { leaderExitConfirmation = $0 }
    }

    func waitForConfirmedShutdown() async {
        if didDescendantExit && shutdownCalls > 2 { return }
        await withCheckedContinuation { confirmedShutdown = $0 }
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
