import Foundation

struct ProviderLoginProvider: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let isAvailable: Bool
    let isAuthenticated: Bool

    var companyName: String {
        Self.companyName(id: id, fallback: name)
    }

    static func companyName(id: String, fallback: String) -> String {
        switch id {
        case "cursor": "Cursor"
        case "openai-codex": "OpenAI"
        case "anthropic": "Anthropic"
        case "google-gemini-cli": "Google"
        default: fallback
        }
    }
}
