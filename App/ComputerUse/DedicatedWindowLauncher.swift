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

enum DedicatedWindowLaunchError: Error, Sendable, Equatable {
    case applicationNotFound
    case noNewWindow
    case ambiguousNewWindows
    case unsupportedNewWindow
}

struct WorkspaceApplicationLauncher: AgentApplicationLaunching {
    func launch(_ application: AgentApplication) async throws -> AgentLaunchedProcess {
        switch application.strategy {
        case .newInstance:
            guard let applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: application.bundleIdentifier)
            else { throw DedicatedWindowLaunchError.applicationNotFound }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            let runningApplication = try await NSWorkspace.shared.openApplication(
                at: applicationURL,
                configuration: configuration)
            return AgentLaunchedProcess(processID: runningApplication.processIdentifier)
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

    init(
        provider: any AgentDesktopProvider,
        applicationLauncher: any AgentApplicationLaunching = WorkspaceApplicationLauncher()
    ) {
        self.provider = provider
        self.applicationLauncher = applicationLauncher
    }

    func launch(
        _ application: AgentApplication,
        in desktop: PreparedAgentDesktop
    ) async throws -> WindowLaunchResult {
        let before = Set(try await provider.listWindows().map(\.id))
        let events = try await provider.watchWindows()

        let process = try await applicationLauncher.launch(application)
        let after = try await waitForStableWindows(events: events, after: before)
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
        events: AsyncStream<AgentWindowEvent>,
        after before: Set<String>
    ) async throws -> [AgentWindow] {
        let watcherTask = Task {
            for await _ in events {
                if Task.isCancelled { return }
            }
        }
        defer { watcherTask.cancel() }

        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(5)
        var previousNewWindowIDs: Set<String>?
        while clock.now < deadline {
            try Task.checkCancellation()
            let windows = try await provider.listWindows()
            let newWindowIDs = Set(windows.map(\.id)).subtracting(before)
            if !newWindowIDs.isEmpty, newWindowIDs == previousNewWindowIDs {
                return windows
            }
            previousNewWindowIDs = newWindowIDs.isEmpty ? nil : newWindowIDs
            try await Task.sleep(for: .milliseconds(100))
        }
        throw DedicatedWindowLaunchError.noNewWindow
    }
}

extension DedicatedWindowLauncher: DedicatedWindowLaunching {}
