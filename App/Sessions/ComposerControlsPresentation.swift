import Foundation

enum ComposerControlsPresentation {
    static func authenticatedModels(
        catalog: [ComposerModelInfo],
        authenticatedProviderIDs: Set<String>
    ) -> [ComposerModelInfo] {
        catalog.filter { authenticatedProviderIDs.contains($0.provider) }
    }

    static func thinkingOptions(for model: ComposerModelInfo?) -> [String] {
        guard let model, !model.thinkingEfforts.isEmpty else { return [] }
        return ["auto"] + model.thinkingEfforts
    }

    static func supportsFastMode(model: ComposerModelInfo?) -> Bool {
        guard let model else { return false }
        return serviceTierFamily(for: model) != nil
    }

    static func roleDefaultValue(provider: String, modelID: String) -> String {
        "\(provider)/\(modelID)"
    }

    static func parseRoleDefault(_ value: String) -> (provider: String, modelID: String)? {
        guard let slash = value.firstIndex(of: "/") else { return nil }
        let provider = String(value[..<slash])
        let modelID = String(value[value.index(after: slash)...])
        guard !provider.isEmpty, !modelID.isEmpty else { return nil }
        return (provider, modelID)
    }

    // ponytail: mirrors @oh-my-pi/pi-ai serviceTierFamily; OpenAI relay ids use prefix heuristics only
    private static func serviceTierFamily(for model: ComposerModelInfo) -> String? {
        let provider = model.provider
        if provider == "openrouter" {
            let id = model.id.lowercased()
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
        return isOpenAIModelID(model.id)
    }

    private static func isOpenAIModelID(_ id: String) -> Bool {
        let lower = id.lowercased()
        return lower.hasPrefix("gpt-") || lower.hasPrefix("o1") || lower.hasPrefix("o3") || lower.hasPrefix("o4") || lower.hasPrefix("chatgpt-")
    }
}
