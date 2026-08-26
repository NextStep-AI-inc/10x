import AppKit
import Foundation

enum AgentApplicationLaunchStrategy: Sendable {
    case newInstance
    case newWindow
}

struct AgentApplication: Sendable, Equatable {
    let bundleIdentifier: String
    let strategy: AgentApplicationLaunchStrategy
}

struct AgentLaunchedProcess: Sendable, Equatable {
    let processID: Int32
}

protocol AgentApplicationLaunching: Sendable {
    func launch(_ application: AgentApplication) async throws -> AgentLaunchedProcess
}

protocol WorkspaceApplicationOpening: Sendable {
    func applicationURL(withBundleIdentifier bundleIdentifier: String) async -> URL?
    func openApplication(
        at applicationURL: URL,
        configuration: NSWorkspace.OpenConfiguration
    ) async throws -> AgentLaunchedProcess
}

struct SystemWorkspaceApplicationOpener: WorkspaceApplicationOpening {
    func applicationURL(withBundleIdentifier bundleIdentifier: String) async -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    func openApplication(
        at applicationURL: URL,
        configuration: NSWorkspace.OpenConfiguration
    ) async throws -> AgentLaunchedProcess {
        let runningApplication = try await NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: configuration)
        return AgentLaunchedProcess(processID: runningApplication.processIdentifier)
    }
}

enum DedicatedWindowLaunchError: Error, Sendable, Equatable {
    case applicationNotFound
    case noNewWindow
    case ambiguousNewWindows
    case unsupportedNewWindow
}

struct WorkspaceApplicationLauncher: AgentApplicationLaunching {
    private let opener: any WorkspaceApplicationOpening

    init(opener: any WorkspaceApplicationOpening = SystemWorkspaceApplicationOpener()) {
        self.opener = opener
    }

    func launch(_ application: AgentApplication) async throws -> AgentLaunchedProcess {
        switch application.strategy {
        case .newInstance:
            guard let applicationURL = await opener.applicationURL(
                withBundleIdentifier: application.bundleIdentifier)
            else { throw DedicatedWindowLaunchError.applicationNotFound }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            configuration.activates = false
            return try await opener.openApplication(
                at: applicationURL,
                configuration: configuration)
        case .newWindow:
            // No generic documented native new-window action exists. Callers may
            // only provide this strategy once an application-specific seam exists.
            throw DedicatedWindowLaunchError.unsupportedNewWindow
        }
    }
}

struct WindowLaunchResult: Sendable, Equatable {
    let processID: Int32
    let ownedWindows: [AgentOwnedWindow]
}

protocol DedicatedWindowLaunching: Sendable {
    func launch(
        _ application: AgentApplication,
        in desktop: PreparedAgentDesktop
    ) async throws -> WindowLaunchResult
}

struct DedicatedWindowLauncher: Sendable {
    private let provider: any AgentDesktopProvider
    private let applicationLauncher: any AgentApplicationLaunching
    private let quiescenceInterval: Duration

    init(
        provider: any AgentDesktopProvider,
        applicationLauncher: any AgentApplicationLaunching = WorkspaceApplicationLauncher(),
        quiescenceInterval: Duration = .seconds(1)
    ) {
        self.provider = provider
        self.applicationLauncher = applicationLauncher
        self.quiescenceInterval = quiescenceInterval
    }

    func launch(
        _ application: AgentApplication,
        in desktop: PreparedAgentDesktop
    ) async throws -> WindowLaunchResult {
        let before = Set(try await provider.listWindows().map(\.id))
        let events = try await provider.watchWindows()
        let eventMonitor = AgentWindowEventMonitor()
        let watcherTask = Task {
            for await event in events {
                await eventMonitor.record(event)
            }
        }
        defer { watcherTask.cancel() }

        let process = try await applicationLauncher.launch(application)
        let after = try await waitForStableWindows(
            eventMonitor: eventMonitor,
            after: before)
        let created = after.filter { !before.contains($0.id) }
        guard !created.isEmpty else { throw DedicatedWindowLaunchError.noNewWindow }

        let correlated = created.filter { $0.processID == process.processID }
        guard created.count == 1, correlated.count == 1 else {
            throw DedicatedWindowLaunchError.ambiguousNewWindows
        }

        let claimedWindow = correlated[0]
        if let workspaceID = desktop.workspaceID {
            try await provider.move(windowID: claimedWindow.id, to: workspaceID)
        }
        return WindowLaunchResult(
            processID: process.processID,
            ownedWindows: [AgentOwnedWindow(claimedWindow)])
    }

    private func waitForStableWindows(
        eventMonitor: AgentWindowEventMonitor,
        after before: Set<String>
    ) async throws -> [AgentWindow] {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(5)
        var newWindowIDs = Set<String>()
        var eventRevision = await eventMonitor.revision()
        var lastChange = clock.now
        while clock.now < deadline {
            try Task.checkCancellation()
            if let failure = await eventMonitor.failure() { throw failure }
            let windows = try await provider.listWindows()
            let currentNewWindowIDs = Set(windows.map(\.id)).subtracting(before)
            let currentEventRevision = await eventMonitor.revision()
            if currentNewWindowIDs != newWindowIDs || currentEventRevision != eventRevision {
                newWindowIDs = currentNewWindowIDs
                eventRevision = currentEventRevision
                lastChange = clock.now
            }
            if !newWindowIDs.isEmpty, clock.now - lastChange >= quiescenceInterval {
                return windows
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw DedicatedWindowLaunchError.noNewWindow
    }
}

extension DedicatedWindowLauncher: DedicatedWindowLaunching {}

private actor AgentWindowEventMonitor {
    private var changeRevision = 0
    private var watcherFailure: AgentDesktopProviderError?

    func record(_ event: AgentWindowEvent) {
        changeRevision += 1
        if case .failed(let error) = event { watcherFailure = error }
    }

    func revision() -> Int { changeRevision }
    func failure() -> AgentDesktopProviderError? { watcherFailure }
}
