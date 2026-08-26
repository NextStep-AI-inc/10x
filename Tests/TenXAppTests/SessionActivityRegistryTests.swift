import Foundation
import Testing
@testable import TenXApp

@MainActor @Test func activityCountsAreDeduplicatedAndProviderChangesReplaceContribution() {
    let registry = SessionActivityRegistry()
    let first = UUID()
    let second = UUID()

    registry.update(sessionID: first, providerID: "anthropic", isGenerating: true)
    registry.update(sessionID: second, providerID: "anthropic", isGenerating: true)
    #expect(registry.activeCounts == ["anthropic": 2])

    registry.update(sessionID: first, providerID: "openai-codex", isGenerating: true)
    #expect(registry.activeCounts == ["anthropic": 1, "openai-codex": 1])

    registry.update(sessionID: second, providerID: "anthropic", isGenerating: false)
    #expect(registry.activeCounts == ["openai-codex": 1])

    registry.remove(sessionID: first)
    #expect(registry.activeCounts.isEmpty)
}

@MainActor @Test func repeatingAnUpdateDoesNotDoubleCount() {
    let registry = SessionActivityRegistry()
    let sessionID = UUID()

    registry.update(sessionID: sessionID, providerID: "anthropic", isGenerating: true)
    registry.update(sessionID: sessionID, providerID: "anthropic", isGenerating: true)

    #expect(registry.activeCounts == ["anthropic": 1])
}

@MainActor @Test func missingOrEmptyProviderIDsDoNotContributeButNonemptyIDsDo() {
    let registry = SessionActivityRegistry()

    registry.update(sessionID: UUID(), providerID: nil, isGenerating: true)
    registry.update(sessionID: UUID(), providerID: "  \t\n", isGenerating: true)
    registry.update(sessionID: UUID(), providerID: "future-provider", isGenerating: true)

    #expect(registry.activeCounts == ["future-provider": 1])
}

@MainActor @Test func removingMissingSessionIDIsHarmless() {
    let registry = SessionActivityRegistry()

    registry.remove(sessionID: UUID())

    #expect(registry.activeCounts.isEmpty)
}
