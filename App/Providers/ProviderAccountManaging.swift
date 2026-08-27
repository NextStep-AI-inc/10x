import Foundation
import OmpKit

enum ProviderAccountCapability: Sendable, Equatable {
    case accountRouting
    case providerOnly
}

typealias ProviderAccountRemovalResult = RemoveProviderAccountResult

protocol ProviderAccountManaging: Sendable {
    func accounts(providerID: String) async throws -> [ProviderAccountSummary]
    func accountUsage(providerID: String) async throws -> [ProviderAccountUsage]
    func removeAccount(
        providerID: String,
        accountRef: String
    ) async throws -> ProviderAccountRemovalResult
}

/// Outcome of asking a `ProviderAccountRouting` backend to make an account
/// the one in force for a session.
enum ProviderAccountRouteOutcome: Sendable, Equatable {
    /// The account is in force for the session now.
    case applied
    /// The session is mid-turn; the coordinator re-issues when it goes idle.
    case queued
    /// Stock OMP cannot re-route a live session; the caller must re-adopt it.
    case restartRequired
}

/// The shared write interface both tier backends implement:
/// `ProviderAccountExtensionBackend` (t2, extension-mediated) and
/// `ProviderAccountPinBackend` (t1, stock-OMP session-file writes).
/// `ProviderAccountExtensionBackend` never returns `.restartRequired`, and
/// `ProviderAccountPinBackend` never returns `.queued` — queueing for the
/// stock tier is the coordinator's existing behavior, applied before the
/// restart.
protocol ProviderAccountRouting: Sendable {
    func route(
        providerID: String,
        accountRef: String,
        sessionID: UUID
    ) async throws -> ProviderAccountRouteOutcome
}
