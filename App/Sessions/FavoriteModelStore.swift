import Foundation

/// Ordered model favorites stored by 10x without changing OMP's shared config.
@MainActor
struct FavoriteModelStore: Sendable {
    static let defaultKey = "favorite-model-keys"

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = Self.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    func toggle(_ model: ComposerModelInfo) {
        let prior = defaults.stringArray(forKey: key) ?? []
        if prior.contains(model.id) {
            defaults.set(prior.filter { $0 != model.id }, forKey: key)
        } else {
            defaults.set([model.id] + prior, forKey: key)
        }
    }

    func rankedModels(from catalog: [ComposerModelInfo]) -> [ComposerModelInfo] {
        let keys = defaults.stringArray(forKey: key) ?? []
        return keys.compactMap { key in
            catalog.first { $0.id == key }
        }
    }
}
