import Foundation
import Testing
@testable import TenXApp

private let favoriteAnthropic = ComposerModelInfo(
    modelID: "claude-opus", name: "Claude Opus", provider: "anthropic",
    api: "anthropic-messages", thinkingEfforts: ["low", "high"], requiresEffort: false)
private let favoriteCursor = ComposerModelInfo(
    modelID: "claude-opus", name: "Claude Opus", provider: "cursor",
    api: "cursor-agent", thinkingEfforts: [], requiresEffort: false)
private let favoriteCodex = ComposerModelInfo(
    modelID: "gpt-codex", name: "GPT Codex", provider: "openai-codex",
    api: "openai-codex-responses", thinkingEfforts: ["medium"], requiresEffort: true)

@MainActor
private func favoriteDefaults(_ name: String = #function) -> UserDefaults {
    let suiteName = "favorites.\(name)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

@MainActor
@Test func favoriteModelsPersistAcrossStoreInstances() {
    let defaults = favoriteDefaults()
    FavoriteModelStore(defaults: defaults).toggle(favoriteAnthropic)

    let reopened = FavoriteModelStore(defaults: defaults)

    #expect(reopened.rankedModels(from: [favoriteAnthropic]) == [favoriteAnthropic])
}

@MainActor
@Test func favoriteIdentityIncludesTheProvider() {
    let store = FavoriteModelStore(defaults: favoriteDefaults())
    store.toggle(favoriteAnthropic)
    store.toggle(favoriteCursor)

    #expect(store.rankedModels(from: [favoriteAnthropic, favoriteCursor]).map(\.id) == [
        "cursor/claude-opus",
        "anthropic/claude-opus",
    ])
}

@MainActor
@Test func togglingAFavoriteRemovesOnlyThatIdentity() {
    let store = FavoriteModelStore(defaults: favoriteDefaults())
    store.toggle(favoriteAnthropic)
    store.toggle(favoriteCursor)
    store.toggle(favoriteCursor)

    #expect(store.rankedModels(from: [favoriteAnthropic, favoriteCursor]) == [favoriteAnthropic])
}

@MainActor
@Test func missingFavoriteCatalogEntriesStayStored() {
    let defaults = favoriteDefaults()
    let store = FavoriteModelStore(defaults: defaults)
    store.toggle(favoriteAnthropic)
    store.toggle(favoriteCodex)

    #expect(store.rankedModels(from: [favoriteCodex]) == [favoriteCodex])
    #expect(FavoriteModelStore(defaults: defaults)
        .rankedModels(from: [favoriteAnthropic, favoriteCodex]) == [favoriteCodex, favoriteAnthropic])
}
