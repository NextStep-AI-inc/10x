import Foundation

struct ProviderLoginProvider: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let isAvailable: Bool
    let isAuthenticated: Bool
}
