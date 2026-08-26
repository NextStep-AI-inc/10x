import Foundation

struct ComposerModelInfo: Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let provider: String
    let api: String?
    let thinkingEfforts: [String]
    let requiresEffort: Bool
}
