import Foundation
import OmpKit

struct AgentDesktopReadiness: Sendable, Equatable {
    let preferredFailure: ProviderAvailability?
    let backgroundFallbackAvailable: Bool
}

struct AgentDesktopCoordinator: Sendable {
    private let providers: [AgentDesktopProviderKind: any AgentDesktopProvider]

    init(providers: [any AgentDesktopProvider] = [
        AeroSpaceProvider(),
        HammerspoonProvider(),
        BackgroundProvider(),
    ]) {
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.kind, $0) })
    }

    func readiness(preference: AgentDesktopPreference) async -> AgentDesktopReadiness {
        let candidateKinds = candidates(for: preference)
        let preferredFailure: ProviderAvailability?
        if let preferredKind = candidateKinds.first, let provider = providers[preferredKind] {
            let probe = await provider.probe()
            preferredFailure = probe.availability == .healthy ? nil : probe.availability
        } else {
            preferredFailure = .missing
        }
        let backgroundFallbackAvailable: Bool
        if preference == .backgroundOnly {
            backgroundFallbackAvailable = false
        } else if let background = providers[.background] {
            backgroundFallbackAvailable = await background.probe().availability == .healthy
        } else {
            backgroundFallbackAvailable = false
        }
        return AgentDesktopReadiness(
            preferredFailure: preferredFailure,
            backgroundFallbackAvailable: backgroundFallbackAvailable)
    }

    func prepare(
        preference: AgentDesktopPreference,
        sessionToken: String
    ) async throws -> PreparedAgentDesktop {
        for kind in candidates(for: preference) {
            guard let provider = providers[kind] else { continue }
            let probe = await provider.probe()
            guard probe.availability == .healthy else {
                if preference != .automatic {
                    throw AgentDesktopProviderError.unavailable(kind, probe.availability)
                }
                continue
            }
            return try await provider.prepare(sessionToken: sessionToken)
        }
        let unavailableKind = candidates(for: preference).first ?? .background
        throw AgentDesktopProviderError.unavailable(unavailableKind, .missing)
    }

    func listWindows(in prepared: PreparedAgentDesktop) async throws -> [AgentWindow] {
        guard let provider = providers[prepared.provider] else {
            throw AgentDesktopProviderError.unavailable(prepared.provider, .missing)
        }
        return try await provider.listWindows()
    }

    func watchWindows(in prepared: PreparedAgentDesktop) async throws -> AsyncStream<AgentWindowEvent> {
        guard let provider = providers[prepared.provider] else {
            throw AgentDesktopProviderError.unavailable(prepared.provider, .missing)
        }
        return try await provider.watchWindows()
    }

    func dedicatedWindowLauncher(
        for prepared: PreparedAgentDesktop
    ) throws -> DedicatedWindowLauncher {
        guard let provider = providers[prepared.provider] else {
            throw AgentDesktopProviderError.unavailable(prepared.provider, .missing)
        }
        return DedicatedWindowLauncher(provider: provider)
    }

    func cleanup(manifest: AgentDesktopManifest) async -> CleanupReport {
        guard let provider = providers[manifest.provider],
              let liveWindows = try? await provider.listWindows()
        else {
            return CleanupReport(
                preservedApplicationNames: sanitizedApplicationNames(for: manifest.ownedWindows),
                restoredWindowCount: 0)
        }
        let liveWindowIDs = Set(liveWindows.map(\.id))
        var restoredWindowCount = 0
        for window in manifest.ownedWindows where liveWindowIDs.contains(window.id) {
            guard let originalWorkspaceID = window.originalWorkspaceID else { continue }
            do {
                try await provider.restore(windowID: window.id, to: originalWorkspaceID)
                restoredWindowCount += 1
            } catch {
                continue
            }
        }
        return CleanupReport(
            preservedApplicationNames: sanitizedApplicationNames(for: manifest.ownedWindows),
            restoredWindowCount: restoredWindowCount)
    }

    @MainActor
    func probePreparedWorkspace(
        _ prepared: PreparedAgentDesktop,
        probe: @escaping @Sendable (String, String) async throws -> ComputerProbeResult
    ) async throws -> ComputerProbeResult {
        guard let provider = providers[prepared.provider] else {
            throw AgentDesktopProviderError.unavailable(prepared.provider, .missing)
        }
        let window = AgentDesktopProbeWindow()
        let target = try window.open()
        defer { window.close() }
        if let workspaceID = prepared.workspaceID {
            try await provider.move(windowID: target.windowID, to: workspaceID)
        }
        let result = try await probe(target.windowID, target.verificationText)
        guard result.captureSucceeded,
              !prepared.capabilities.canInputInBackground || result.backgroundInputSucceeded == true
        else { throw AgentDesktopProviderError.probeFailed(prepared.provider) }
        return result
    }

    private func candidates(for preference: AgentDesktopPreference) -> [AgentDesktopProviderKind] {
        switch preference {
        case .automatic: [.aeroSpace, .hammerspoon, .background]
        case .aeroSpace: [.aeroSpace]
        case .hammerspoon: [.hammerspoon]
        case .backgroundOnly: [.background]
        }
    }

    private func sanitizedApplicationNames(for windows: [AgentOwnedWindow]) -> [String] {
        Array(Set(windows.map { sanitizedApplicationName($0.applicationName) })).sorted()
    }

    private func sanitizedApplicationName(_ name: String) -> String {
        let leaf = name.split(separator: "/").last.map(String.init) ?? "Application"
        let allowed = leaf.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
                || CharacterSet.whitespaces.contains($0)
                || "._-".unicodeScalars.contains($0)
        }
        let sanitized = String(String.UnicodeScalarView(allowed)).prefix(64)
        return sanitized.isEmpty ? "Application" : String(sanitized)
    }
}
