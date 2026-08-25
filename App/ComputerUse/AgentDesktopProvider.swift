import Foundation

enum AgentDesktopProviderKind: String, Codable, Sendable, CaseIterable {
    case aeroSpace
    case hammerspoon
    case background
}

enum AgentDesktopPreference: String, Codable, Sendable, CaseIterable {
    case automatic
    case aeroSpace
    case hammerspoon
    case backgroundOnly
}

struct ProviderCapabilities: Sendable, Equatable {
    let canIsolate: Bool
    let canMoveWithoutFocus: Bool
    let canCaptureOffscreen: Bool
    let canInputInBackground: Bool

    static let isolated = ProviderCapabilities(
        canIsolate: true,
        canMoveWithoutFocus: true,
        canCaptureOffscreen: true,
        canInputInBackground: true)
    static let background = ProviderCapabilities(
        canIsolate: false,
        canMoveWithoutFocus: false,
        canCaptureOffscreen: false,
        canInputInBackground: false)
}

enum ProviderAvailability: Sendable, Equatable {
    case healthy
    case missing
    case incompatible
    case failed
}

struct ProviderProbe: Sendable, Equatable {
    let availability: ProviderAvailability
    let integrationVersion: String?
    let capabilities: ProviderCapabilities
}

protocol AgentDesktopProvider: Sendable {
    var kind: AgentDesktopProviderKind { get }
    func probe() async -> ProviderProbe
    func prepare(sessionToken: String) async throws -> PreparedAgentDesktop
    func listWindows() async throws -> [AgentWindow]
    func watchWindows() async throws -> AsyncStream<AgentWindowEvent>
    func move(windowID: String, to workspaceID: String) async throws
    func restore(windowID: String, to workspaceID: String) async throws
    func openVisibly(workspaceID: String) async throws
    func release(workspaceID: String) async
}

struct PreparedAgentDesktop: Sendable, Equatable {
    let provider: AgentDesktopProviderKind
    let workspaceID: String?
    let capabilities: ProviderCapabilities
}

struct AgentWindow: Sendable, Equatable, Hashable {
    let id: String
    let processID: Int32
    let app: String
    let workspaceID: String?
}

enum AgentWindowEvent: Sendable, Equatable {
    case appeared(AgentWindow)
    case disappeared(id: String)
}

enum AgentDesktopProviderError: Error, Sendable, Equatable {
    case unavailable(AgentDesktopProviderKind, ProviderAvailability)
    case invalidSessionToken
    case invalidWindowIdentifier
    case invalidWorkspaceIdentifier
    case malformedResponse(AgentDesktopProviderKind)
    case probeFailed(AgentDesktopProviderKind)
}
