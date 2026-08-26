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
