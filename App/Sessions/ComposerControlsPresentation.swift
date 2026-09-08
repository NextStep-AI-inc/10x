import Foundation

enum ComposerControlsPresentation {
    static func authenticatedModels(
        catalog: [ComposerModelInfo],
        authenticatedProviderIDs: Set<String>
    ) -> [ComposerModelInfo] {
        catalog.filter { authenticatedProviderIDs.contains($0.provider) }
    }

    static func matching(_ models: [ComposerModelInfo], query: String) -> [ComposerModelInfo] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return models }
        return models.filter { model in
            model.name.lowercased().contains(needle)
                || model.provider.lowercased().contains(needle)
        }
    }

    /// Preserves first-appearance provider order and catalog order within a provider.
    static func groupedByProvider(
        _ models: [ComposerModelInfo]
    ) -> [(provider: String, models: [ComposerModelInfo])] {
        var order: [String] = []
        var buckets: [String: [ComposerModelInfo]] = [:]
        for model in models {
            if buckets[model.provider] == nil { order.append(model.provider) }
            buckets[model.provider, default: []].append(model)
        }
        return order.map { (provider: $0, models: buckets[$0] ?? []) }
    }

    static func thinkingOptions(for model: ComposerModelInfo?) -> [String] {
        guard let model, !model.thinkingEfforts.isEmpty else { return [] }
        // A model that requires an explicit effort must never be offered "auto".
        return model.requiresEffort ? model.thinkingEfforts : ["auto"] + model.thinkingEfforts
    }

    /// Keeps a level the incoming model still offers, else "auto", else the middle effort.
    static func resolvedThinkingLevel(
        current: String,
        for model: ComposerModelInfo?
    ) -> String {
        let options = thinkingOptions(for: model)
        guard !options.isEmpty else { return current }
        if options.contains(current) { return current }
        if options.contains("auto") { return "auto" }
        return options[options.count / 2]
    }

    static func supportsFastMode(model: ComposerModelInfo?) -> Bool {
        guard let model else { return false }
        return serviceTierFamily(for: model) != nil
    }

    static func roleDefaultValue(provider: String, modelID: String) -> String {
        "\(provider)/\(modelID)"
    }

    // ponytail: mirrors @oh-my-pi/pi-ai serviceTierFamily; OpenAI relay ids use prefix heuristics only
    private static func serviceTierFamily(for model: ComposerModelInfo) -> String? {
        let provider = model.provider
        if provider == "openrouter" {
            let id = model.modelID.lowercased()
            if id.hasPrefix("anthropic/") { return "anthropic" }
            if id.hasPrefix("google/") { return "google" }
            if id.hasPrefix("openai/") { return "openai" }
            return nil
        }
        if provider == "openai" || provider == "openai-codex" { return "openai" }
        if model.api == "anthropic-messages" { return "anthropic" }
        if provider == "google" || provider == "google-vertex" { return "google" }
        if isOpenAIServiceTierModel(model) { return "openai" }
        return nil
    }

    private static func isOpenAIServiceTierModel(_ model: ComposerModelInfo) -> Bool {
        if model.provider == "fireworks" || model.provider == "github-copilot" { return false }
        guard let api = model.api else { return false }
        let openAIAPIs: Set<String> = ["openai-completions", "openai-responses", "openai-codex-responses"]
        guard openAIAPIs.contains(api) else { return false }
        return isOpenAIModelID(model.modelID)
    }

    private static func isOpenAIModelID(_ id: String) -> Bool {
        let lower = id.lowercased()
        return lower.hasPrefix("gpt-") || lower.hasPrefix("o1") || lower.hasPrefix("o3") || lower.hasPrefix("o4") || lower.hasPrefix("chatgpt-")
    }

    static let recentSectionID = "recent"
    static let favoritesSectionID = "favorites"

    static func pickerSections(
        models: [ComposerModelInfo],
        recents: [ComposerModelInfo],
        favorites: [ComposerModelInfo] = [],
        query: String
    ) -> [ModelPickerSection] {
        let favoriteIDs = Set(favorites.map(\.id))
        let filteredFavorites = matching(favorites, query: query)
        let filteredCatalog = matching(models, query: query)
            .filter { !favoriteIDs.contains($0.id) }
        let providerSections = groupedByProvider(filteredCatalog).map { group in
            ModelPickerSection(
                id: group.provider,
                title: group.provider.uppercased(),
                models: group.models,
                showsProviderTag: false)
        }
        let favoriteSections = filteredFavorites.isEmpty ? [] : [
            ModelPickerSection(
                id: favoritesSectionID,
                title: "FAVORITES",
                models: filteredFavorites,
                showsProviderTag: true),
        ]
        let isSearching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let visibleRecents = recents.filter { !favoriteIDs.contains($0.id) }
        guard !isSearching, !visibleRecents.isEmpty else {
            return favoriteSections + providerSections
        }
        return favoriteSections + [
            ModelPickerSection(
                id: recentSectionID,
                title: "RECENT",
                models: visibleRecents,
                showsProviderTag: true),
        ] + providerSections
    }

    static func triggerTitle(for model: ComposerModelInfo?) -> String {
        model?.name ?? "Model"
    }

    static func rowAccessibilityValue(provider: String, isSelected: Bool) -> String {
        isSelected ? "\(provider), selected" : provider
    }
}
