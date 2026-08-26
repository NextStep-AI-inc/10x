import SwiftUI
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

@Test func plainReturnSendsWhenSendIsAvailable() {
    var didSend = false
    let result = ComposerView.handleReturn(modifiers: [], canSend: true) { didSend = true }
    #expect(didSend)
    #expect(result == .handled)
}

@Test func plainReturnIsSwallowedWhenSendIsUnavailable() {
    var didSend = false
    let result = ComposerView.handleReturn(modifiers: [], canSend: false) { didSend = true }
    #expect(!didSend)
    #expect(result == .handled)
}

@Test func modifiedReturnFallsThroughToTextView() {
    for modifiers: EventModifiers in [[.shift], [.option], [.command], [.control], [.shift, .capsLock]] {
        var didSend = false
        let result = ComposerView.handleReturn(modifiers: modifiers, canSend: true) { didSend = true }
        #expect(!didSend)
        #expect(result == .ignored)
    }
}

@Test func capsLockDoesNotBlockSending() {
    var didSend = false
    let result = ComposerView.handleReturn(modifiers: [.capsLock], canSend: true) { didSend = true }
    #expect(didSend)
    #expect(result == .handled)
}

private let pickerCatalog = [
    ComposerModelInfo(modelID: "claude-opus-4-5", name: "Claude Opus 4.5", provider: "anthropic", api: "anthropic-messages", thinkingEfforts: ["low", "high"], requiresEffort: false),
    ComposerModelInfo(modelID: "claude-sonnet-4-5", name: "Claude Sonnet 4.5", provider: "anthropic", api: "anthropic-messages", thinkingEfforts: ["low", "high"], requiresEffort: false),
    ComposerModelInfo(modelID: "gpt-5.2-codex", name: "GPT-5.2 Codex", provider: "openai-codex", api: "openai-codex-responses", thinkingEfforts: ["medium"], requiresEffort: true),
    ComposerModelInfo(modelID: "claude-opus-4-5", name: "Claude Opus 4.5", provider: "cursor", api: "cursor-agent", thinkingEfforts: [], requiresEffort: false),
]

@Test func emptyQueryMatchesEveryModel() {
    #expect(ComposerControlsPresentation.matching(pickerCatalog, query: "") == pickerCatalog)
    #expect(ComposerControlsPresentation.matching(pickerCatalog, query: "   ") == pickerCatalog)
}

@Test func queryMatchesModelNameCaseInsensitively() {
    let matches = ComposerControlsPresentation.matching(pickerCatalog, query: "OPUS")
    #expect(matches.map(\.id) == ["anthropic/claude-opus-4-5", "cursor/claude-opus-4-5"])
}

@Test func queryMatchesProviderIdentifier() {
    let matches = ComposerControlsPresentation.matching(pickerCatalog, query: "cursor")
    #expect(matches.map(\.id) == ["cursor/claude-opus-4-5"])
}

@Test func queryMatchesPartialProviderIdentifier() {
    let matches = ComposerControlsPresentation.matching(pickerCatalog, query: "openai")
    #expect(matches.map(\.id) == ["openai-codex/gpt-5.2-codex"])
}

@Test func unmatchedQueryReturnsNothing() {
    #expect(ComposerControlsPresentation.matching(pickerCatalog, query: "llama").isEmpty)
}

@Test func groupingKeepsProviderAndCatalogOrder() {
    let groups = ComposerControlsPresentation.groupedByProvider(pickerCatalog)
    #expect(groups.map(\.provider) == ["anthropic", "openai-codex", "cursor"])
    #expect(groups[0].models.map(\.modelID) == ["claude-opus-4-5", "claude-sonnet-4-5"])
    #expect(groups[2].models.map(\.modelID) == ["claude-opus-4-5"])
}

@Test func groupingLosesNoModels() {
    let groups = ComposerControlsPresentation.groupedByProvider(pickerCatalog)
    #expect(groups.flatMap(\.models).count == pickerCatalog.count)
    #expect(ComposerControlsPresentation.groupedByProvider([]).isEmpty)
}

private let requiredEffortModel = ComposerModelInfo(
    modelID: "gpt-5.2-codex", name: "GPT-5.2 Codex", provider: "openai-codex",
    api: "openai-codex-responses", thinkingEfforts: ["low", "medium", "high"],
    requiresEffort: true)

private let optionalEffortModel = ComposerModelInfo(
    modelID: "claude-opus-4-5", name: "Claude Opus 4.5", provider: "anthropic",
    api: "anthropic-messages", thinkingEfforts: ["low", "high"], requiresEffort: false)

private let noEffortModel = ComposerModelInfo(
    modelID: "claude-opus-4-5", name: "Claude Opus 4.5", provider: "cursor",
    api: "cursor-agent", thinkingEfforts: [], requiresEffort: false)

@Test func thinkingOptionsOmitAutoWhenEffortIsRequired() {
    #expect(ComposerControlsPresentation.thinkingOptions(for: requiredEffortModel)
        == ["low", "medium", "high"])
}

@Test func thinkingOptionsKeepAutoWhenEffortIsOptional() {
    #expect(ComposerControlsPresentation.thinkingOptions(for: optionalEffortModel)
        == ["auto", "low", "high"])
}

@Test func resolvedThinkingLevelKeepsAStillValidLevel() {
    #expect(ComposerControlsPresentation.resolvedThinkingLevel(
        current: "high", for: requiredEffortModel) == "high")
    #expect(ComposerControlsPresentation.resolvedThinkingLevel(
        current: "auto", for: optionalEffortModel) == "auto")
}

@Test func resolvedThinkingLevelFallsBackToAutoWhenOffered() {
    #expect(ComposerControlsPresentation.resolvedThinkingLevel(
        current: "medium", for: optionalEffortModel) == "auto")
}

@Test func resolvedThinkingLevelFallsBackToMiddleEffortWhenAutoIsUnavailable() {
    #expect(ComposerControlsPresentation.resolvedThinkingLevel(
        current: "auto", for: requiredEffortModel) == "medium")
}

@Test func resolvedThinkingLevelIsUnchangedForModelsWithoutThinking() {
    #expect(ComposerControlsPresentation.resolvedThinkingLevel(
        current: "high", for: noEffortModel) == "high")
    #expect(ComposerControlsPresentation.resolvedThinkingLevel(
        current: "high", for: nil) == "high")
}
