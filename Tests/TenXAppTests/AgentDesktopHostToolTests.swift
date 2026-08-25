import OmpKit
import Testing
@testable import TenXApp

@Test func resolverAcceptsAnInstalledBundleIdentifier() {
    let resolver = WorkspaceApplicationResolver(catalog: StaticApplicationCatalog(applications: [
        AgentInstalledApplication(
            bundleIdentifier: "com.example.writer",
            localizedDisplayName: "Écriture",
            bundleName: "Writer"),
    ]))

    #expect(resolver.resolve(application: "com.example.writer")
        == AgentApplication(bundleIdentifier: "com.example.writer", strategy: .newInstance))
}

@Test func resolverAcceptsAnInstalledLocalizedDisplayName() {
    let resolver = WorkspaceApplicationResolver(catalog: StaticApplicationCatalog(applications: [
        AgentInstalledApplication(
            bundleIdentifier: "com.example.writer",
            localizedDisplayName: "Écriture",
            bundleName: "Writer"),
    ]))

    #expect(resolver.resolve(application: "ecriture")
        == AgentApplication(bundleIdentifier: "com.example.writer", strategy: .newInstance))
}

@Test func resolverAcceptsAnInstalledBundleName() {
    let resolver = WorkspaceApplicationResolver(catalog: StaticApplicationCatalog(applications: [
        AgentInstalledApplication(
            bundleIdentifier: "com.example.writer",
            localizedDisplayName: "Écriture",
            bundleName: "Writer"),
    ]))

    #expect(resolver.resolve(application: "writer")
        == AgentApplication(bundleIdentifier: "com.example.writer", strategy: .newInstance))
}

@Test func resolverRejectsAnUnavailableApplication() {
    let resolver = WorkspaceApplicationResolver(catalog: StaticApplicationCatalog(applications: []))

    #expect(resolver.resolve(application: "not-installed") == nil)
}

@Test func hostToolBorrowsOnlyACurrentlyEnumeratedWindowWithoutMovingIt() async {
    let provider = HostToolProvider(windows: [
        AgentWindow(id: "auth-window", processID: 8, app: "Safari", workspaceID: "desktop-two"),
    ])
    let coordinator = AgentDesktopCoordinator(providers: [provider])
    let tool = AgentDesktopHostTool(coordinator: coordinator, launcher: EmptyDedicatedWindowLauncher())
    let call = HostToolCall(
        id: "host-1",
        toolCallID: "tool-1",
        name: "agent_desktop",
        arguments: .object([
            "action": .string("borrow"),
            "windowId": .string("auth-window"),
        ]))

    let outcome = await tool.handle(
        call,
        in: PreparedAgentDesktop(provider: .aeroSpace, workspaceID: "10x-session", capabilities: .isolated),
        manifest: AgentDesktopManifest(provider: .aeroSpace, workspaceID: "10x-session"))

    #expect(!outcome.isError)
    #expect(outcome.manifest.borrowedWindowIDs == ["auth-window"])
    #expect(outcome.result["content"]?.arrayValue?.first?["text"]?.stringValue == "Safari: auth-window")
    #expect(await provider.movedWindowIDs().isEmpty)
}

@Test func hostToolCancellationReturnsOneErrorAndRetainsALateLaunchClaimForCleanup() async {
    let provider = HostToolProvider(windows: [])
    let coordinator = AgentDesktopCoordinator(providers: [provider])
    let launcher = BlockingDedicatedWindowLauncher()
    let tool = AgentDesktopHostTool(
        coordinator: coordinator,
        launcher: launcher,
        applicationResolver: StaticApplicationResolver())
    let call = HostToolCall(
        id: "host-2",
        toolCallID: "tool-2",
        name: "agent_desktop",
        arguments: .object([
            "action": .string("launch"),
            "application": .string("TextEdit"),
        ]))
    let prepared = PreparedAgentDesktop(
        provider: .aeroSpace,
        workspaceID: "10x-session",
        capabilities: .isolated)
    let launch = Task {
        await tool.handle(
            call,
            in: prepared,
            manifest: AgentDesktopManifest(prepared: prepared))
    }

    await launcher.waitUntilStarted()
    await tool.cancel(callID: "host-2")
    await launcher.finish(with: WindowLaunchResult(
        processID: 9,
        ownedWindows: [AgentOwnedWindow(AgentWindow(
            id: "late-window",
            processID: 9,
            app: "TextEdit",
            workspaceID: "desktop-one"))]))
    let outcome = await launch.value

    #expect(outcome.isError)
    #expect(outcome.manifest.ownedWindows.map(\.id) == ["late-window"])
    #expect(outcome.result["content"]?.arrayValue?.first?["text"]?.stringValue
        == "[AgentDesktopHostTool:handle] Launch cancelled — {request: sanitized}")
}

@Test func hostToolCancellationKeepsAnAlreadyMovedWindowForCleanup() async {
    let provider = HostToolProvider(windows: [
        AgentWindow(id: "moved-window", processID: 9, app: "TextEdit", workspaceID: "10x-session"),
    ])
    let coordinator = AgentDesktopCoordinator(providers: [provider])
    let launcher = MovedThenBlockingDedicatedWindowLauncher(provider: provider)
    let tool = AgentDesktopHostTool(
        coordinator: coordinator,
        launcher: launcher,
        applicationResolver: StaticApplicationResolver())
    let call = HostToolCall(
        id: "host-moved",
        toolCallID: "tool-moved",
        name: "agent_desktop",
        arguments: .object([
            "action": .string("launch"),
            "application": .string("TextEdit"),
        ]))
    let prepared = PreparedAgentDesktop(
        provider: .aeroSpace,
        workspaceID: "10x-session",
        capabilities: .isolated)
    let launch = Task {
        await tool.handle(
            call,
            in: prepared,
            manifest: AgentDesktopManifest(prepared: prepared))
    }

    await launcher.waitUntilMoved()
    await tool.cancel(callID: "host-moved")
    await launcher.finish()
    let outcome = await launch.value
    let cleanup = await coordinator.cleanup(manifest: outcome.manifest)

    #expect(outcome.isError)
    #expect(outcome.manifest.ownedWindows.map(\.id) == ["moved-window"])
    #expect(cleanup.restoredWindowCount == 1)
    #expect(await provider.restoredWindowIDs() == ["moved-window"])
}

@Test func hostToolRecordsAmbiguousLaunchesWithoutClaimingAWindow() async {
    let provider = HostToolProvider(windows: [])
    let coordinator = AgentDesktopCoordinator(providers: [provider])
    let tool = AgentDesktopHostTool(
        coordinator: coordinator,
        launcher: AmbiguousDedicatedWindowLauncher(),
        applicationResolver: StaticApplicationResolver())
    let call = HostToolCall(
        id: "host-3",
        toolCallID: "tool-3",
        name: "agent_desktop",
        arguments: .object([
            "action": .string("launch"),
            "application": .string("TextEdit"),
        ]))

    let outcome = await tool.handle(
        call,
        in: PreparedAgentDesktop(provider: .aeroSpace, workspaceID: "10x-session", capabilities: .isolated),
        manifest: AgentDesktopManifest(provider: .aeroSpace, workspaceID: "10x-session"))

    #expect(outcome.isError)
    #expect(outcome.manifest.ownedWindows.isEmpty)
    #expect(outcome.manifest.ambiguousApplications == ["TextEdit"])
}

@Test func hostToolCancellationSuppressesALateAmbiguousLaunchResult() async {
    let provider = HostToolProvider(windows: [])
    let coordinator = AgentDesktopCoordinator(providers: [provider])
    let launcher = BlockingAmbiguousDedicatedWindowLauncher()
    let tool = AgentDesktopHostTool(
        coordinator: coordinator,
        launcher: launcher,
        applicationResolver: StaticApplicationResolver())
    let call = HostToolCall(
        id: "host-4",
        toolCallID: "tool-4",
        name: "agent_desktop",
        arguments: .object([
            "action": .string("launch"),
            "application": .string("TextEdit"),
        ]))
    let prepared = PreparedAgentDesktop(
        provider: .aeroSpace,
        workspaceID: "10x-session",
        capabilities: .isolated)
    let launch = Task {
        await tool.handle(
            call,
            in: prepared,
            manifest: AgentDesktopManifest(prepared: prepared))
    }

    await launcher.waitUntilStarted()
    await tool.cancel(callID: "host-4")
    await launcher.finish()
    let outcome = await launch.value

    #expect(outcome.isError)
    #expect(outcome.manifest.ownedWindows.isEmpty)
    #expect(outcome.manifest.ambiguousApplications.isEmpty)
    #expect(outcome.result["content"]?.arrayValue?.first?["text"]?.stringValue
        == "[AgentDesktopHostTool:handle] Launch cancelled — {request: sanitized}")
}

private actor HostToolProvider: AgentDesktopProvider {
    nonisolated let kind: AgentDesktopProviderKind = .aeroSpace
    private let windows: [AgentWindow]
    private var movedIDs: [String] = []
    private var restoredIDs: [String] = []

    init(windows: [AgentWindow]) {
        self.windows = windows
    }

    func probe() async -> ProviderProbe {
        ProviderProbe(availability: .healthy, integrationVersion: "1.0", capabilities: .isolated)
    }

    func prepare(sessionToken: String) async throws -> PreparedAgentDesktop {
        PreparedAgentDesktop(provider: kind, workspaceID: "10x-session", capabilities: .isolated)
    }

    func listWindows() async throws -> [AgentWindow] { windows }
    func watchWindows() async throws -> AsyncStream<AgentWindowEvent> {
        AsyncStream { continuation in continuation.finish() }
    }
    func move(windowID: String, to workspaceID: String) async throws { movedIDs.append(windowID) }
    func restore(windowID: String, to workspaceID: String) async throws { restoredIDs.append(windowID) }
    func openVisibly(workspaceID: String) async throws {}
    func release(workspaceID: String) async {}

    func movedWindowIDs() -> [String] { movedIDs }
    func restoredWindowIDs() -> [String] { restoredIDs }
}

private struct EmptyDedicatedWindowLauncher: DedicatedWindowLaunching {
    func launch(_ application: AgentApplication, in desktop: PreparedAgentDesktop) async throws -> WindowLaunchResult {
        throw DedicatedWindowLaunchError.noNewWindow
    }
}

private struct AmbiguousDedicatedWindowLauncher: DedicatedWindowLaunching {
    func launch(_ application: AgentApplication, in desktop: PreparedAgentDesktop) async throws -> WindowLaunchResult {
        throw DedicatedWindowLaunchError.ambiguousNewWindows
    }
}

private actor BlockingDedicatedWindowLauncher: DedicatedWindowLaunching {
    private var resultContinuation: CheckedContinuation<WindowLaunchResult, Never>?
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var hasStarted = false

    func launch(_ application: AgentApplication, in desktop: PreparedAgentDesktop) async throws -> WindowLaunchResult {
        hasStarted = true
        startContinuation?.resume()
        startContinuation = nil
        return await withCheckedContinuation { continuation in
            resultContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
    }

    func finish(with result: WindowLaunchResult) {
        resultContinuation?.resume(returning: result)
        resultContinuation = nil
    }
}

private actor BlockingAmbiguousDedicatedWindowLauncher: DedicatedWindowLaunching {
    private var completion: CheckedContinuation<Void, Never>?
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var hasStarted = false

    func launch(_ application: AgentApplication, in desktop: PreparedAgentDesktop) async throws -> WindowLaunchResult {
        hasStarted = true
        startContinuation?.resume()
        startContinuation = nil
        await withCheckedContinuation { continuation in
            completion = continuation
        }
        throw DedicatedWindowLaunchError.ambiguousNewWindows
    }

    func waitUntilStarted() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
    }

    func finish() {
        completion?.resume()
        completion = nil
    }
}

private actor MovedThenBlockingDedicatedWindowLauncher: DedicatedWindowLaunching {
    private let provider: HostToolProvider
    private var completion: CheckedContinuation<Void, Never>?
    private var movedContinuation: CheckedContinuation<Void, Never>?
    private var hasMoved = false

    init(provider: HostToolProvider) {
        self.provider = provider
    }

    func launch(_ application: AgentApplication, in desktop: PreparedAgentDesktop) async throws -> WindowLaunchResult {
        try await provider.move(windowID: "moved-window", to: "10x-session")
        hasMoved = true
        movedContinuation?.resume()
        movedContinuation = nil
        await withCheckedContinuation { continuation in
            completion = continuation
        }
        return WindowLaunchResult(
            processID: 9,
            ownedWindows: [AgentOwnedWindow(AgentWindow(
                id: "moved-window",
                processID: 9,
                app: "TextEdit",
                workspaceID: "desktop-one"))])
    }

    func waitUntilMoved() async {
        guard !hasMoved else { return }
        await withCheckedContinuation { continuation in
            movedContinuation = continuation
        }
    }

    func finish() {
        completion?.resume()
        completion = nil
    }
}

private struct StaticApplicationResolver: AgentApplicationResolving {
    func resolve(application: String) -> AgentApplication? {
        AgentApplication(bundleIdentifier: "com.apple.TextEdit", strategy: .newInstance)
    }
}

private struct StaticApplicationCatalog: AgentApplicationCatalog {
    let applications: [AgentInstalledApplication]

    func application(bundleIdentifier: String) -> AgentInstalledApplication? {
        applications.first { $0.bundleIdentifier == bundleIdentifier }
    }

    func installedApplications() -> [AgentInstalledApplication] { applications }
}
