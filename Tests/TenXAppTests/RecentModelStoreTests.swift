import Foundation
import Testing
@testable import TenXApp

private func makeDefaults(_ name: String) -> UserDefaults {
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

private let opusAnthropic = ComposerModelInfo(
    modelID: "claude-opus-4-5", name: "Claude Opus 4.5", provider: "anthropic",
    api: "anthropic-messages", thinkingEfforts: ["low", "high"], requiresEffort: false)
private let opusCursor = ComposerModelInfo(
    modelID: "claude-opus-4-5", name: "Claude Opus 4.5", provider: "cursor",
    api: "cursor-agent", thinkingEfforts: [], requiresEffort: false)
private let codex = ComposerModelInfo(
    modelID: "gpt-5.2-codex", name: "GPT-5.2 Codex", provider: "openai-codex",
    api: "openai-codex-responses", thinkingEfforts: ["medium"], requiresEffort: true)
private let sonnet = ComposerModelInfo(
    modelID: "claude-sonnet-4-5", name: "Claude Sonnet 4.5", provider: "anthropic",
    api: "anthropic-messages", thinkingEfforts: ["low", "high"], requiresEffort: false)

@MainActor
@Test func recentModelsAreMostRecentFirst() {
    let store = RecentModelStore(defaults: makeDefaults("recents.order"), key: "k")
    store.recordSelection(opusAnthropic)
    store.recordSelection(codex)

    let ranked = store.rankedModels(from: [opusAnthropic, codex, sonnet])
    #expect(ranked.map(\.id) == ["openai-codex/gpt-5.2-codex", "anthropic/claude-opus-4-5"])
}

@MainActor
@Test func reselectingAModelMovesItToTheFrontWithoutDuplicating() {
    let store = RecentModelStore(defaults: makeDefaults("recents.dedupe"), key: "k")
    store.recordSelection(opusAnthropic)
    store.recordSelection(codex)
    store.recordSelection(opusAnthropic)

    let ranked = store.rankedModels(from: [opusAnthropic, codex])
    #expect(ranked.map(\.id) == ["anthropic/claude-opus-4-5", "openai-codex/gpt-5.2-codex"])
}

@MainActor
@Test func recentModelsAreCappedAtCapacity() {
    let store = RecentModelStore(defaults: makeDefaults("recents.cap"), key: "k")
    store.recordSelection(opusAnthropic)
    store.recordSelection(codex)
    store.recordSelection(sonnet)
    store.recordSelection(opusCursor)

    let ranked = store.rankedModels(from: [opusAnthropic, codex, sonnet, opusCursor])
    #expect(ranked.count == RecentModelStore.capacity)
    #expect(ranked.map(\.id) == [
        "cursor/claude-opus-4-5",
        "anthropic/claude-sonnet-4-5",
        "openai-codex/gpt-5.2-codex",
    ])
}

@MainActor
@Test func recentModelsDropKeysMissingFromTheCatalog() {
    let store = RecentModelStore(defaults: makeDefaults("recents.stale"), key: "k")
    store.recordSelection(opusAnthropic)
    store.recordSelection(codex)

    let ranked = store.rankedModels(from: [codex])
    #expect(ranked.map(\.id) == ["openai-codex/gpt-5.2-codex"])
}

@MainActor
@Test func sameModelFromTwoProvidersIsTrackedSeparately() {
    let store = RecentModelStore(defaults: makeDefaults("recents.dupes"), key: "k")
    store.recordSelection(opusAnthropic)
    store.recordSelection(opusCursor)

    let ranked = store.rankedModels(from: [opusAnthropic, opusCursor])
    #expect(ranked.map(\.id) == ["cursor/claude-opus-4-5", "anthropic/claude-opus-4-5"])
}

@MainActor
@Test func anEmptyStoreRanksNothing() {
    let store = RecentModelStore(defaults: makeDefaults("recents.empty"), key: "k")
    #expect(store.rankedModels(from: [opusAnthropic]).isEmpty)
}
