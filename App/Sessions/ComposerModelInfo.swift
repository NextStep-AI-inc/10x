import Foundation

struct ComposerModelInfo: Equatable, Sendable, Identifiable {
    /// OMP model id (not unique across providers).
    let modelID: String
    let name: String
    let provider: String
    let api: String?
    let thinkingEfforts: [String]
    let requiresEffort: Bool

    /// Stable ForEach / selection key across multi-provider catalogs.
    var id: String { "\(provider)/\(modelID)" }
}

struct ModelPickerSection: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let models: [ComposerModelInfo]
    /// Recent rows sit outside their provider section, so they name their provider inline.
    let showsProviderTag: Bool
}

struct ComposerLiveSelection: Equatable, Sendable {
    var provider: String?
    var modelID: String?
    var thinkingLevel: String?
    var fastModeEnabled: Bool
}
