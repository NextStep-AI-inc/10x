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

@Test func pickerSectionsLeadWithRecentsThenProviders() {
    let recents = [pickerCatalog[3], pickerCatalog[0]]
    let sections = ComposerControlsPresentation.pickerSections(
        models: pickerCatalog, recents: recents, query: "")

    #expect(sections.map(\.id) == ["recent", "anthropic", "openai-codex", "cursor"])
    #expect(sections[0].title == "RECENT")
    #expect(sections[0].showsProviderTag)
    #expect(sections[0].models.map(\.id) == ["cursor/claude-opus-4-5", "anthropic/claude-opus-4-5"])
    #expect(sections[1].title == "ANTHROPIC")
    #expect(!sections[1].showsProviderTag)
}

@Test func pickerSectionsOmitRecentsWhenEmpty() {
    let sections = ComposerControlsPresentation.pickerSections(
        models: pickerCatalog, recents: [], query: "")
    #expect(sections.map(\.id) == ["anthropic", "openai-codex", "cursor"])
}

@Test func pickerSectionsOmitRecentsWhileSearching() {
    let sections = ComposerControlsPresentation.pickerSections(
        models: pickerCatalog, recents: [pickerCatalog[0]], query: "opus")
    #expect(sections.map(\.id) == ["anthropic", "cursor"])
    #expect(sections.flatMap(\.models).count == 2)
}

@Test func pickerSectionsPutFilteredFavoritesFirstWithoutDuplicatingThem() {
    let favorites = [pickerCatalog[3], pickerCatalog[0]]
    let sections = ComposerControlsPresentation.pickerSections(
        models: pickerCatalog,
        recents: [pickerCatalog[0], pickerCatalog[2]],
        favorites: favorites,
        query: "opus")

    #expect(sections.map(\.id) == ["favorites"])
    #expect(sections[0].title == "FAVORITES")
    #expect(sections[0].showsProviderTag)
    #expect(sections[0].models.map(\.id) == [
        "cursor/claude-opus-4-5",
        "anthropic/claude-opus-4-5",
    ])
    #expect(Set(sections.flatMap(\.models).map(\.id)).count == 2)
}

@Test func pickerSectionsRemoveFavoritesFromRecentsAndProviderGroups() {
    let favorite = pickerCatalog[0]
    let sections = ComposerControlsPresentation.pickerSections(
        models: pickerCatalog,
        recents: [favorite, pickerCatalog[2]],
        favorites: [favorite],
        query: "")

    #expect(sections.map(\.id) == ["favorites", "recent", "anthropic", "openai-codex", "cursor"])
    #expect(sections[0].models.map(\.id) == [favorite.id])
    #expect(sections[1].models.map(\.id) == [pickerCatalog[2].id])
    #expect(sections.dropFirst(2).flatMap(\.models).contains(where: { $0.id == favorite.id }) == false)
}

@Test func pickerSectionsDropProvidersWithNoMatches() {
    let sections = ComposerControlsPresentation.pickerSections(
        models: pickerCatalog, recents: [], query: "sonnet")
    #expect(sections.map(\.id) == ["anthropic"])
    #expect(sections[0].models.map(\.modelID) == ["claude-sonnet-4-5"])
}

@Test func pickerSectionsAreEmptyWhenNothingMatches() {
    #expect(ComposerControlsPresentation.pickerSections(
        models: pickerCatalog, recents: [], query: "llama").isEmpty)
}

@Test func triggerTitleNamesTheModelOrFallsBack() {
    #expect(ComposerControlsPresentation.triggerTitle(for: pickerCatalog[0]) == "Claude Opus 4.5")
    #expect(ComposerControlsPresentation.triggerTitle(for: nil) == "Model")
}

@Test func rowAccessibilityValueNamesTheProviderAndSelection() {
    #expect(ComposerControlsPresentation.rowAccessibilityValue(
        provider: "anthropic", isSelected: true) == "anthropic, selected")
    #expect(ComposerControlsPresentation.rowAccessibilityValue(
        provider: "cursor", isSelected: false) == "cursor")
}

@Test func listHeightGrowsWithContentAndStopsAtTheCap() {
    #expect(ModelPickerMetrics.listHeight(rowCount: 2, sectionCount: 1)
        == 2 * ModelPickerMetrics.rowHeight + ModelPickerMetrics.headerHeight)
    #expect(ModelPickerMetrics.listHeight(rowCount: 0, sectionCount: 0)
        == 2 * ModelPickerMetrics.rowHeight)
    #expect(ModelPickerMetrics.listHeight(rowCount: 400, sectionCount: 40)
        == ModelPickerMetrics.maxListHeight)
}

@Test func panelIsNeverNarrowerThanItsTrigger() {
    #expect(ModelPickerMetrics.bottomWidth(triggerWidth: 40) == 44)
    #expect(ModelPickerMetrics.bottomWidth(triggerWidth: 120) == 120)
    #expect(ModelPickerMetrics.bottomWidth(triggerWidth: 900)
        == ModelPickerMetrics.panelWidth)
}

@Test func effortLayoutUsesEveryAvailableColumnAtTheApprovedWidths() {
    #expect(ModelPickerMetrics.effortColumnCount(optionCount: 6, panelWidth: 440) == 6)
    #expect(ModelPickerMetrics.effortRowCount(optionCount: 6, panelWidth: 440) == 1)
    #expect(ModelPickerMetrics.effortColumnCount(optionCount: 6, panelWidth: 360) == 3)
    #expect(ModelPickerMetrics.effortRowCount(optionCount: 6, panelWidth: 360) == 2)
    #expect(ModelPickerMetrics.effortColumnCount(optionCount: 4, panelWidth: 360) == 4)
    #expect(ModelPickerMetrics.effortRowCount(optionCount: 4, panelWidth: 360) == 1)
}

@Test func panelWidthUsesTheAvailableWindowSpaceUpToTheApprovedWidth() {
    #expect(ModelPickerMetrics.resolvedPanelWidth(availableWidth: 800) == 440)
    #expect(ModelPickerMetrics.resolvedPanelWidth(availableWidth: 360) == 360)
    #expect(ModelPickerMetrics.resolvedPanelWidth(availableWidth: 200) == 200)
}

@Test func effortLabelsShowTheCompleteSupportedNames() {
    #expect(["auto", "low", "medium", "high", "xhigh", "max"].map(
        ModelPickerMetrics.effortLabel) == ["Auto", "Low", "Medium", "High", "Extra high", "Max"])
}

@Test func settingsHeightAccountsForTheEffortHeadingRowsAndFastMode() {
    #expect(ModelPickerMetrics.settingsHeight(optionCount: 6, panelWidth: 440, showsFastMode: true)
        == ModelPickerMetrics.separatorHeight
            + ModelPickerMetrics.effortTitleHeight
            + ModelPickerMetrics.effortSegmentHeight
            + ModelPickerMetrics.settingsRowHeight)
    #expect(ModelPickerMetrics.settingsHeight(optionCount: 6, panelWidth: 360, showsFastMode: true)
        == ModelPickerMetrics.separatorHeight
            + ModelPickerMetrics.effortTitleHeight
            + 2 * ModelPickerMetrics.effortSegmentHeight
            + ModelPickerMetrics.effortGridSpacing
            + ModelPickerMetrics.settingsRowHeight)
}

@Test func flatIndexCountsOnlyTheRowsAboveASection() {
    let sections = ComposerControlsPresentation.pickerSections(
        models: pickerCatalog,
        recents: [pickerCatalog[3]],
        query: "")
    // RECENT(1) + ANTHROPIC(2) + OPENAI-CODEX(1) + CURSOR(1)
    #expect(sections.map(\.models.count) == [1, 2, 1, 1])
    #expect(ModelPickerFlyout.flatIndex(sections: sections, section: 0, row: 0) == 0)
    #expect(ModelPickerFlyout.flatIndex(sections: sections, section: 1, row: 0) == 1)
    #expect(ModelPickerFlyout.flatIndex(sections: sections, section: 1, row: 1) == 2)
    #expect(ModelPickerFlyout.flatIndex(sections: sections, section: 2, row: 0) == 3)
    #expect(ModelPickerFlyout.flatIndex(sections: sections, section: 3, row: 0) == 4)
    #expect(sections.flatMap(\.models).count == 5)
}

@Test func highlightMovementClampsToTheVisibleRows() {
    #expect(ModelPickerFlyout.highlightIndex(from: 0, delta: 1, rowCount: 5) == 1)
    #expect(ModelPickerFlyout.highlightIndex(from: 3, delta: -1, rowCount: 5) == 2)
    #expect(ModelPickerFlyout.highlightIndex(from: 0, delta: -1, rowCount: 5) == 0)
    #expect(ModelPickerFlyout.highlightIndex(from: 4, delta: 1, rowCount: 5) == 4)
    #expect(ModelPickerFlyout.highlightIndex(from: 9, delta: 1, rowCount: 5) == 4)
    #expect(ModelPickerFlyout.highlightIndex(from: 3, delta: 1, rowCount: 0) == 0)
}

@Test func scrollTargetsAreSectionQualifiedSoDuplicateRowsDoNotCollide() {
    let sections = ComposerControlsPresentation.pickerSections(
        models: pickerCatalog,
        recents: [pickerCatalog[0]],
        query: "")
    let targets = sections.flatMap { section in
        section.models.map {
            ModelPickerFlyout.rowID(section: section.id, model: $0.id)
        }
    }
    // The selected model renders twice with one model id; the targets differ.
    #expect(targets.first == "recent/anthropic/claude-opus-4-5")
    #expect(targets.contains("anthropic/anthropic/claude-opus-4-5"))
    #expect(Set(targets).count == targets.count)
}
