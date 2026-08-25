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

private actor FakeAgentDesktopProvider: AgentDesktopProvider {
    nonisolated let kind: AgentDesktopProviderKind
    private let result: ProviderAvailability
    private var prepareTokens: [String] = []

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
    func release(workspaceID: String) async {}

    func recordedPrepareTokens() -> [String] { prepareTokens }
}
