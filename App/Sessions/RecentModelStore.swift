import Foundation

/// Most-recently-used models, app-local. OMP's own config is shared with the CLI,
/// so 10x interface state is not written there.
@MainActor
struct RecentModelStore: Sendable {
    static let defaultKey = "recent-model-keys"
    static let capacity = 3

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = Self.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    func recordSelection(_ model: ComposerModelInfo) {
        let prior = defaults.stringArray(forKey: key) ?? []
        let keys = [model.id] + prior.filter { $0 != model.id }
        defaults.set(Array(keys.prefix(Self.capacity)), forKey: key)
    }

    func rankedModels(from catalog: [ComposerModelInfo]) -> [ComposerModelInfo] {
        let keys = defaults.stringArray(forKey: key) ?? []
        return keys.compactMap { key in
            catalog.first { $0.id == key }
        }
    }
}
