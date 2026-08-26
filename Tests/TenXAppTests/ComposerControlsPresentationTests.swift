import Testing
@testable import TenXApp

@Test func authenticatedModelsKeepOnlySignedInProviders() {
    let catalog = [
        ComposerModelInfo(id: "a", name: "A", provider: "anthropic", api: "anthropic-messages", thinkingEfforts: ["high"], requiresEffort: false),
        ComposerModelInfo(id: "b", name: "B", provider: "cursor", api: "cursor-agent", thinkingEfforts: [], requiresEffort: false),
    ]
    let filtered = ComposerControlsPresentation.authenticatedModels(
        catalog: catalog,
        authenticatedProviderIDs: ["anthropic"])
    #expect(filtered.map(\.id) == ["a"])
}

@Test func thinkingOptionsIncludeAutoWhenEffortsExist() {
    let model = ComposerModelInfo(id: "m", name: "M", provider: "anthropic", api: nil, thinkingEfforts: ["low", "high"], requiresEffort: false)
    #expect(ComposerControlsPresentation.thinkingOptions(for: model) == ["auto", "low", "high"])
    #expect(ComposerControlsPresentation.thinkingOptions(for: nil).isEmpty)
}

@Test func supportsFastModeMatchesOMPServiceTierFamilies() {
    let anthropic = ComposerModelInfo(id: "x", name: "X", provider: "amazon-bedrock", api: "anthropic-messages", thinkingEfforts: [], requiresEffort: false)
    let cursor = ComposerModelInfo(id: "y", name: "Y", provider: "cursor", api: "cursor-agent", thinkingEfforts: [], requiresEffort: false)
    let codex = ComposerModelInfo(id: "z", name: "Z", provider: "openai-codex", api: nil, thinkingEfforts: [], requiresEffort: false)
    #expect(ComposerControlsPresentation.supportsFastMode(model: anthropic))
    #expect(!ComposerControlsPresentation.supportsFastMode(model: cursor))
    #expect(ComposerControlsPresentation.supportsFastMode(model: codex))
}
