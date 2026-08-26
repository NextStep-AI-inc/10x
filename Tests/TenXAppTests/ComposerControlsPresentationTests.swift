import Testing
@testable import TenXApp

@Test func authenticatedModelsKeepOnlySignedInProviders() {
    let catalog = [
        ComposerModelInfo(modelID: "a", name: "A", provider: "anthropic", api: "anthropic-messages", thinkingEfforts: ["high"], requiresEffort: false),
        ComposerModelInfo(modelID: "b", name: "B", provider: "cursor", api: "cursor-agent", thinkingEfforts: [], requiresEffort: false),
    ]
    let filtered = ComposerControlsPresentation.authenticatedModels(
        catalog: catalog,
        authenticatedProviderIDs: ["anthropic"])
    #expect(filtered.map(\.id) == ["anthropic/a"])
}

@Test func thinkingOptionsIncludeAutoWhenEffortsExist() {
    let model = ComposerModelInfo(modelID: "m", name: "M", provider: "anthropic", api: nil, thinkingEfforts: ["low", "high"], requiresEffort: false)
    #expect(ComposerControlsPresentation.thinkingOptions(for: model) == ["auto", "low", "high"])
    #expect(ComposerControlsPresentation.thinkingOptions(for: nil).isEmpty)
}

@Test func supportsFastModeMatchesOMPServiceTierFamilies() {
    let anthropic = ComposerModelInfo(modelID: "x", name: "X", provider: "amazon-bedrock", api: "anthropic-messages", thinkingEfforts: [], requiresEffort: false)
    let cursor = ComposerModelInfo(modelID: "y", name: "Y", provider: "cursor", api: "cursor-agent", thinkingEfforts: [], requiresEffort: false)
    let codex = ComposerModelInfo(modelID: "z", name: "Z", provider: "openai-codex", api: nil, thinkingEfforts: [], requiresEffort: false)
    #expect(ComposerControlsPresentation.supportsFastMode(model: anthropic))
    #expect(!ComposerControlsPresentation.supportsFastMode(model: cursor))
    #expect(ComposerControlsPresentation.supportsFastMode(model: codex))
}
