import Testing
@testable import TenXApp

@Test func automaticSelectionUsesTheStrongestHealthyProvider() async throws {
    let aero = FakeAgentDesktopProvider(kind: .aeroSpace, probe: .healthy)
    let hammerspoon = FakeAgentDesktopProvider(kind: .hammerspoon, probe: .healthy)
    let background = FakeAgentDesktopProvider(kind: .background, probe: .healthy)
    let coordinator = AgentDesktopCoordinator(providers: [aero, hammerspoon, background])

    let prepared = try await coordinator.prepare(preference: .automatic, sessionToken: "abc123")

    #expect(prepared.provider == .aeroSpace)
    #expect(await aero.recordedPrepareTokens() == ["abc123"])
    #expect(await hammerspoon.recordedPrepareTokens().isEmpty)
    #expect(await background.recordedPrepareTokens().isEmpty)
}

@Test func unhealthyExplicitProviderDoesNotChangeThePreference() async {
    let coordinator = AgentDesktopCoordinator(providers: [
        FakeAgentDesktopProvider(kind: .aeroSpace, probe: .missing),
        FakeAgentDesktopProvider(kind: .background, probe: .healthy),
    ])

    let readiness = await coordinator.readiness(preference: .aeroSpace)

    #expect(readiness.preferredFailure != nil)
    #expect(readiness.backgroundFallbackAvailable)
}

@Test func automaticSelectionSkipsUnhealthyProvidersInStrengthOrder() async throws {
    let aero = FakeAgentDesktopProvider(kind: .aeroSpace, probe: .failed)
    let hammerspoon = FakeAgentDesktopProvider(kind: .hammerspoon, probe: .healthy)
    let background = FakeAgentDesktopProvider(kind: .background, probe: .healthy)
    let coordinator = AgentDesktopCoordinator(providers: [aero, hammerspoon, background])

    let prepared = try await coordinator.prepare(preference: .automatic, sessionToken: "abc123")

    #expect(prepared.provider == .hammerspoon)
    #expect(await aero.recordedPrepareTokens().isEmpty)
    #expect(await hammerspoon.recordedPrepareTokens() == ["abc123"])
    #expect(await background.recordedPrepareTokens().isEmpty)
}

@Test func automaticSelectionFallsBackToBackgroundAfterBothIsolationProvidersFail() async throws {
    let aero = FakeAgentDesktopProvider(kind: .aeroSpace, probe: .failed)
    let hammerspoon = FakeAgentDesktopProvider(kind: .hammerspoon, probe: .incompatible)
    let background = FakeAgentDesktopProvider(kind: .background, probe: .healthy)
    let coordinator = AgentDesktopCoordinator(providers: [aero, hammerspoon, background])

    let prepared = try await coordinator.prepare(preference: .automatic, sessionToken: "abc123")

    #expect(prepared.provider == .background)
    #expect(await aero.recordedPrepareTokens().isEmpty)
    #expect(await hammerspoon.recordedPrepareTokens().isEmpty)
    #expect(await background.recordedPrepareTokens() == ["abc123"])
}

@Test func explicitPrepareNeverFallsBackToAnotherProvider() async {
    let aero = FakeAgentDesktopProvider(kind: .aeroSpace, probe: .missing)
    let background = FakeAgentDesktopProvider(kind: .background, probe: .healthy)
    let coordinator = AgentDesktopCoordinator(providers: [aero, background])

    await #expect(throws: AgentDesktopProviderError.self) {
        try await coordinator.prepare(preference: .aeroSpace, sessionToken: "abc123")
    }
    #expect(await background.recordedPrepareTokens().isEmpty)
}

@Test func releaseForwardsOnlyPreparedWorkspacesToTheirProvider() async {
    let provider = FakeAgentDesktopProvider(kind: .aeroSpace, probe: .healthy)
    let coordinator = AgentDesktopCoordinator(providers: [provider])

    await coordinator.release(PreparedAgentDesktop(
        provider: .aeroSpace, workspaceID: "workspace", capabilities: .isolated))
    await coordinator.release(PreparedAgentDesktop(
        provider: .aeroSpace, workspaceID: nil, capabilities: .isolated))

    #expect(await provider.recordedReleasedWorkspaces() == ["workspace"])
}

private actor FakeAgentDesktopProvider: AgentDesktopProvider {
    nonisolated let kind: AgentDesktopProviderKind
    private let result: ProviderAvailability
    private var prepareTokens: [String] = []
    private var releasedWorkspaces: [String] = []

    init(kind: AgentDesktopProviderKind, probe: ProviderAvailability) {
        self.kind = kind
        result = probe
    }

    func probe() async -> ProviderProbe {
        ProviderProbe(
            availability: result,
            integrationVersion: "1.0.0",
            capabilities: .isolated)
    }

    func prepare(sessionToken: String) async throws -> PreparedAgentDesktop {
        prepareTokens.append(sessionToken)
        return PreparedAgentDesktop(provider: kind, workspaceID: "workspace", capabilities: .isolated)
    }

    func listWindows() async throws -> [AgentWindow] { [] }

    func watchWindows() async throws -> AsyncStream<AgentWindowEvent> {
        AsyncStream { continuation in continuation.finish() }
    }

    func move(windowID: String, to workspaceID: String) async throws {}
    func restore(windowID: String, to workspaceID: String) async throws {}
    func openVisibly(workspaceID: String) async throws {}
    func release(workspaceID: String) async { releasedWorkspaces.append(workspaceID) }

    func recordedPrepareTokens() -> [String] { prepareTokens }
    func recordedReleasedWorkspaces() -> [String] { releasedWorkspaces }
}
