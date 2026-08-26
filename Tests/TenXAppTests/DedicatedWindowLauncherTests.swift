import Foundation
import AppKit
import Testing
@testable import TenXApp

@Test func workspaceLauncherOpensANewInstanceWithoutActivatingIt() async throws {
    let opener = RecordingWorkspaceApplicationOpener()
    let launcher = WorkspaceApplicationLauncher(opener: opener)

    let process = try await launcher.launch(AgentApplication(
        bundleIdentifier: "com.apple.TextEdit",
        strategy: .newInstance))

    #expect(process.processID == 99)
    #expect(opener.recordedConfigurations() == [
        RecordedOpenConfiguration(createsNewApplicationInstance: true, activates: false),
    ])
}

@Test func launcherClaimsOnlyTheWindowIDCreatedAfterLaunch() async throws {
    let provider = LaunchingWindowProvider(snapshots: [
        [AgentWindow(id: "existing", processID: 7, app: "TextEdit", workspaceID: "desktop-one")],
        [
            AgentWindow(id: "existing", processID: 7, app: "TextEdit", workspaceID: "desktop-one"),
            AgentWindow(id: "new", processID: 9, app: "TextEdit", workspaceID: "desktop-one"),
        ],
    ])
    let launcher = DedicatedWindowLauncher(
        provider: provider,
        applicationLauncher: StaticApplicationLauncher(processID: 9))

    let result = try await launcher.launch(
        AgentApplication(bundleIdentifier: "com.apple.TextEdit", strategy: .newInstance),
        in: PreparedAgentDesktop(
            provider: .aeroSpace,
            workspaceID: "10x-session",
            capabilities: .isolated))

    #expect(result.ownedWindows.map(\.id) == ["new"])
    #expect(await provider.listWindowRequestCount() >= 3)
    #expect(await provider.movedWindowIDs() == ["new"])
}

@Test func launcherLeavesMultipleUncorrelatedNewWindowsUnmoved() async {
    let provider = LaunchingWindowProvider(snapshots: [
        [AgentWindow(id: "existing", processID: 7, app: "TextEdit", workspaceID: "desktop-one")],
        [
            AgentWindow(id: "existing", processID: 7, app: "TextEdit", workspaceID: "desktop-one"),
            AgentWindow(id: "new-one", processID: 8, app: "TextEdit", workspaceID: "desktop-one"),
            AgentWindow(id: "new-two", processID: 9, app: "TextEdit", workspaceID: "desktop-one"),
        ],
    ])
    let launcher = DedicatedWindowLauncher(
        provider: provider,
        applicationLauncher: StaticApplicationLauncher(processID: 9))

    await #expect(throws: DedicatedWindowLaunchError.self) {
        try await launcher.launch(
            AgentApplication(bundleIdentifier: "com.apple.TextEdit", strategy: .newInstance),
            in: PreparedAgentDesktop(
                provider: .aeroSpace,
                workspaceID: "10x-session",
                capabilities: .isolated))
    }
    #expect(await provider.movedWindowIDs().isEmpty)
}

@Test func launcherDoesNotMoveAWindowBeforeTheNewWindowSetIsQuiescent() async {
    let provider = LaunchingWindowProvider(snapshots: [
        [AgentWindow(id: "existing", processID: 7, app: "TextEdit", workspaceID: "desktop-one")],
        [
            AgentWindow(id: "existing", processID: 7, app: "TextEdit", workspaceID: "desktop-one"),
            AgentWindow(id: "new-one", processID: 9, app: "TextEdit", workspaceID: "desktop-one"),
        ],
        [
            AgentWindow(id: "existing", processID: 7, app: "TextEdit", workspaceID: "desktop-one"),
            AgentWindow(id: "new-one", processID: 9, app: "TextEdit", workspaceID: "desktop-one"),
        ],
        [
            AgentWindow(id: "existing", processID: 7, app: "TextEdit", workspaceID: "desktop-one"),
            AgentWindow(id: "new-one", processID: 9, app: "TextEdit", workspaceID: "desktop-one"),
            AgentWindow(id: "new-two", processID: 8, app: "TextEdit", workspaceID: "desktop-one"),
        ],
    ])
    let launcher = DedicatedWindowLauncher(
        provider: provider,
        applicationLauncher: StaticApplicationLauncher(processID: 9))

    await #expect(throws: DedicatedWindowLaunchError.ambiguousNewWindows) {
        try await launcher.launch(
            AgentApplication(bundleIdentifier: "com.apple.TextEdit", strategy: .newInstance),
            in: PreparedAgentDesktop(
                provider: .aeroSpace,
                workspaceID: "10x-session",
                capabilities: .isolated))
    }

    #expect(await provider.movedWindowIDs().isEmpty)
}

@Test func launcherWaitsForANewWindowToAppearAfterTheLaunch() async throws {
    let provider = LaunchingWindowProvider(snapshots: [
        [AgentWindow(id: "existing", processID: 7, app: "TextEdit", workspaceID: "desktop-one")],
        [AgentWindow(id: "existing", processID: 7, app: "TextEdit", workspaceID: "desktop-one")],
        [
            AgentWindow(id: "existing", processID: 7, app: "TextEdit", workspaceID: "desktop-one"),
            AgentWindow(id: "new", processID: 9, app: "TextEdit", workspaceID: "desktop-one"),
        ],
    ])
    let launcher = DedicatedWindowLauncher(
        provider: provider,
        applicationLauncher: StaticApplicationLauncher(processID: 9))

    let result = try await launcher.launch(
        AgentApplication(bundleIdentifier: "com.apple.TextEdit", strategy: .newInstance),
        in: PreparedAgentDesktop(
            provider: .aeroSpace,
            workspaceID: "10x-session",
            capabilities: .isolated))

    #expect(result.ownedWindows.map(\.id) == ["new"])
}

@Test func launcherStopsTheHammerspoonWatcherWhenApplicationLaunchFails() async throws {
    let runner = LaunchFailureWatchingDesktopRunner()
    let provider = HammerspoonProvider(executable: URL(filePath: "/bin/true"), runner: runner)
    let launcher = DedicatedWindowLauncher(
        provider: provider,
        applicationLauncher: FailingApplicationLauncher())

    await #expect(throws: LaunchFailure.self) {
        try await launcher.launch(
            AgentApplication(bundleIdentifier: "com.apple.TextEdit", strategy: .newInstance),
            in: PreparedAgentDesktop(
                provider: .hammerspoon,
                workspaceID: "1",
                capabilities: .isolated))
    }
    try await Task.sleep(for: .milliseconds(100))

    #expect(await runner.didStop())
}

private actor LaunchingWindowProvider: AgentDesktopProvider {
    nonisolated let kind: AgentDesktopProviderKind = .aeroSpace
    private var snapshots: [[AgentWindow]]
    private var movedIDs: [String] = []
    private var listWindowRequests = 0

    init(snapshots: [[AgentWindow]]) {
        self.snapshots = snapshots
    }

    func probe() async -> ProviderProbe {
        ProviderProbe(availability: .healthy, integrationVersion: "1.0", capabilities: .isolated)
    }

    func prepare(sessionToken: String) async throws -> PreparedAgentDesktop {
        PreparedAgentDesktop(provider: kind, workspaceID: "10x-session", capabilities: .isolated)
    }

    func listWindows() async throws -> [AgentWindow] {
        listWindowRequests += 1
        guard !snapshots.isEmpty else { return [] }
        if snapshots.count == 1 { return snapshots[0] }
        return snapshots.removeFirst()
    }

    func watchWindows() async throws -> AsyncStream<AgentWindowEvent> {
        AsyncStream { continuation in continuation.finish() }
    }

    func move(windowID: String, to workspaceID: String) async throws {
        movedIDs.append(windowID)
    }

    func restore(windowID: String, to workspaceID: String) async throws {}
    func openVisibly(workspaceID: String) async throws {}
    func release(workspaceID: String) async {}

    func movedWindowIDs() -> [String] { movedIDs }
    func listWindowRequestCount() -> Int { listWindowRequests }
}

private struct StaticApplicationLauncher: AgentApplicationLaunching {
    let processID: Int32

    func launch(_ application: AgentApplication) async throws -> AgentLaunchedProcess {
        AgentLaunchedProcess(processID: processID)
    }
}

private struct RecordedOpenConfiguration: Sendable, Equatable {
    let createsNewApplicationInstance: Bool
    let activates: Bool
}

private final class RecordingWorkspaceApplicationOpener: WorkspaceApplicationOpening, @unchecked Sendable {
    private let lock = NSLock()
    private var configurations: [RecordedOpenConfiguration] = []

    func applicationURL(withBundleIdentifier bundleIdentifier: String) -> URL? {
        URL(filePath: "/Applications/TextEdit.app")
    }

    func openApplication(
        at applicationURL: URL,
        configuration: NSWorkspace.OpenConfiguration
    ) async throws -> AgentLaunchedProcess {
        lock.withLock {
            configurations.append(RecordedOpenConfiguration(
                createsNewApplicationInstance: configuration.createsNewApplicationInstance,
                activates: configuration.activates))
        }
        return AgentLaunchedProcess(processID: 99)
    }

    func recordedConfigurations() -> [RecordedOpenConfiguration] {
        lock.withLock { configurations }
    }
}

private enum LaunchFailure: Error { case failed }

private struct FailingApplicationLauncher: AgentApplicationLaunching {
    func launch(_ application: AgentApplication) async throws -> AgentLaunchedProcess {
        throw LaunchFailure.failed
    }
}

private actor LaunchFailureWatchingDesktopRunner: AgentDesktopCommandRunning {
    private var stopped = false

    func run(executable: URL, arguments: [String], timeout: Duration) async throws -> AgentDesktopCommandOutput {
        let command = arguments.last ?? ""
        if command.contains("stopWatcher") {
            stopped = true
        }
        if command.contains("listWindows") {
            return .init(json: .array([]), exitStatus: 0)
        }
        return .init(json: .object(["ok": .bool(true)]), exitStatus: 0)
    }

    func didStop() -> Bool { stopped }
}
