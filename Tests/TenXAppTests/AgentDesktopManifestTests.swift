import Testing
@testable import TenXApp

@Test func manifestRemovesOnlyTheDisappearedWindowMarker() {
    var manifest = AgentDesktopManifest(provider: .aeroSpace, workspaceID: "10x-session")
    manifest.claim(AgentWindow(
        id: "owned-window",
        processID: 7,
        app: "TextEdit",
        workspaceID: "desktop-one"))
    manifest.borrow(windowID: "borrowed-window")

    manifest.apply(.disappeared(id: "borrowed-window"))

    #expect(manifest.ownedWindows.map(\.id) == ["owned-window"])
    #expect(manifest.borrowedWindowIDs.isEmpty)
}

@Test func manifestDoesNotInferAReplacementForADisappearedOwnedWindow() {
    var manifest = AgentDesktopManifest(provider: .aeroSpace, workspaceID: "10x-session")
    manifest.claim(AgentWindow(
        id: "owned-window",
        processID: 7,
        app: "TextEdit",
        workspaceID: "desktop-one"))

    manifest.apply(.disappeared(id: "owned-window"))
    manifest.apply(.appeared(AgentWindow(
        id: "replacement-window",
        processID: 7,
        app: "TextEdit",
        workspaceID: "desktop-one")))

    #expect(manifest.ownedWindows.isEmpty)
    #expect(manifest.borrowedWindowIDs.isEmpty)
}

@Test func cleanupRestoresOnlyLiveOwnedWindowsWithKnownOriginalWorkspaces() async {
    let provider = CleanupWindowProvider(liveWindows: [
        AgentWindow(id: "owned-window", processID: 7, app: "TextEdit", workspaceID: "10x-session"),
        AgentWindow(id: "borrowed-window", processID: 8, app: "Safari", workspaceID: "desktop-two"),
    ])
    let coordinator = AgentDesktopCoordinator(providers: [provider])
    var manifest = AgentDesktopManifest(provider: .aeroSpace, workspaceID: "10x-session")
    manifest.claim(AgentWindow(
        id: "owned-window",
        processID: 7,
        app: "TextEdit",
        workspaceID: "desktop-one"))
    manifest.borrow(windowID: "borrowed-window")
    manifest.recordAmbiguous(application: "Safari")

    let report = await coordinator.cleanup(manifest: manifest)

    #expect(await provider.restoredWindowIDs() == ["owned-window"])
    #expect(report.restoredWindowCount == 1)
    #expect(report.preservedApplicationNames == ["TextEdit"])
}

@Test func coordinatorProvidesTheProviderWatcherForManifestLifecycleTracking() async throws {
    let provider = WindowWatcherProvider()
    let coordinator = AgentDesktopCoordinator(providers: [provider])
    var manifest = AgentDesktopManifest(provider: .aeroSpace, workspaceID: "10x-session")
    manifest.borrow(windowID: "borrowed-window")
    let prepared = PreparedAgentDesktop(provider: .aeroSpace, workspaceID: "10x-session", capabilities: .isolated)

    for await event in try await coordinator.watchWindows(in: prepared) {
        manifest.apply(event)
    }

    #expect(manifest.borrowedWindowIDs.isEmpty)
}

private actor CleanupWindowProvider: AgentDesktopProvider {
    nonisolated let kind: AgentDesktopProviderKind = .aeroSpace
    private let liveWindows: [AgentWindow]
    private var restoredIDs: [String] = []

    init(liveWindows: [AgentWindow]) {
        self.liveWindows = liveWindows
    }

    func probe() async -> ProviderProbe {
        ProviderProbe(availability: .healthy, integrationVersion: "1.0", capabilities: .isolated)
    }

    func prepare(sessionToken: String) async throws -> PreparedAgentDesktop {
        PreparedAgentDesktop(provider: kind, workspaceID: "10x-session", capabilities: .isolated)
    }

    func listWindows() async throws -> [AgentWindow] { liveWindows }
    func watchWindows() async throws -> AsyncStream<AgentWindowEvent> {
        AsyncStream { continuation in continuation.finish() }
    }
    func move(windowID: String, to workspaceID: String) async throws {}
    func restore(windowID: String, to workspaceID: String) async throws {
        restoredIDs.append(windowID)
    }
    func openVisibly(workspaceID: String) async throws {}
    func release(workspaceID: String) async {}

    func restoredWindowIDs() -> [String] { restoredIDs }
}

private struct WindowWatcherProvider: AgentDesktopProvider {
    let kind: AgentDesktopProviderKind = .aeroSpace

    func probe() async -> ProviderProbe {
        ProviderProbe(availability: .healthy, integrationVersion: "1.0", capabilities: .isolated)
    }

    func prepare(sessionToken: String) async throws -> PreparedAgentDesktop {
        PreparedAgentDesktop(provider: kind, workspaceID: "10x-session", capabilities: .isolated)
    }

    func listWindows() async throws -> [AgentWindow] { [] }
    func watchWindows() async throws -> AsyncStream<AgentWindowEvent> {
        AsyncStream { continuation in
            continuation.yield(.disappeared(id: "borrowed-window"))
            continuation.finish()
        }
    }
    func move(windowID: String, to workspaceID: String) async throws {}
    func restore(windowID: String, to workspaceID: String) async throws {}
    func openVisibly(workspaceID: String) async throws {}
    func release(workspaceID: String) async {}
}
