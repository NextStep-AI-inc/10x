import Foundation

struct AgentOwnedWindow: Sendable, Equatable {
    let id: String
    let processID: Int32
    let applicationName: String
    let originalWorkspaceID: String?

    init(_ window: AgentWindow) {
        id = window.id
        processID = window.processID
        applicationName = window.app
        originalWorkspaceID = window.workspaceID
    }
}

struct AgentDesktopManifest: Sendable, Equatable {
    let provider: AgentDesktopProviderKind
    let workspaceID: String?
    private(set) var ownedProcessIDs: Set<Int32> = []
    private(set) var ownedWindows: [AgentOwnedWindow] = []
    private(set) var borrowedWindowIDs: Set<String> = []
    private(set) var ambiguousApplications: Set<String> = []

    init(provider: AgentDesktopProviderKind, workspaceID: String?) {
        self.provider = provider
        self.workspaceID = workspaceID
    }

    init(prepared: PreparedAgentDesktop) {
        provider = prepared.provider
        workspaceID = prepared.workspaceID
    }

    mutating func claim(_ window: AgentWindow) {
        guard !ownedWindows.contains(where: { $0.id == window.id }) else { return }
        ownedProcessIDs.insert(window.processID)
        ownedWindows.append(AgentOwnedWindow(window))
    }

    mutating func claim(_ result: WindowLaunchResult) {
        ownedProcessIDs.insert(result.processID)
        for window in result.ownedWindows where !ownedWindows.contains(where: { $0.id == window.id }) {
            ownedWindows.append(window)
        }
    }

    mutating func borrow(windowID: String) {
        borrowedWindowIDs.insert(windowID)
    }

    mutating func recordAmbiguous(application: String) {
        ambiguousApplications.insert(application)
    }

    mutating func apply(_ event: AgentWindowEvent) {
        guard case .disappeared(let id) = event else { return }
        ownedWindows.removeAll { $0.id == id }
        borrowedWindowIDs.remove(id)
    }
}

struct CleanupReport: Sendable, Equatable {
    let preservedApplicationNames: [String]
    let restoredWindowCount: Int
}
