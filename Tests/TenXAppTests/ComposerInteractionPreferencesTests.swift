import Foundation
import Testing
@testable import TenXApp

@Suite @MainActor struct ComposerInteractionPreferencesTests {
    @Test func defaultsMatchComposerBehavior() throws {
        let defaults = try makeDefaults()
        let preferences = ComposerInteractionPreferences(defaults: defaults, keyPrefix: #function)

        #expect(preferences.defaultSendAction == .steer)
        #expect(preferences.action(for: .enter) == .primary)
        #expect(preferences.action(for: .commandEnter) == .alternate)
        #expect(preferences.action(for: .shiftEnter) == .newline)
    }

    @Test func valuesPersistAcrossInstances() throws {
        let defaults = try makeDefaults()
        let prefix = #function
        let first = ComposerInteractionPreferences(defaults: defaults, keyPrefix: prefix)

        first.defaultSendAction = .followUp
        first.assign(.newline, to: .enter)

        let reloaded = ComposerInteractionPreferences(defaults: defaults, keyPrefix: prefix)
        #expect(reloaded.defaultSendAction == .followUp)
        #expect(reloaded.action(for: .enter) == .newline)
        #expect(reloaded.action(for: .shiftEnter) == .primary)
    }

    @Test func assigningAnExistingActionSwapsMappingsWithoutDuplicates() throws {
        let defaults = try makeDefaults()
        let preferences = ComposerInteractionPreferences(defaults: defaults, keyPrefix: #function)

        preferences.assign(.alternate, to: .enter)

        #expect(preferences.action(for: .enter) == .alternate)
        #expect(preferences.action(for: .commandEnter) == .primary)
        let actions = ComposerReturnShortcut.allCases.map { preferences.action(for: $0) }
        #expect(Set(actions).count == ComposerReturnAction.allCases.count)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "TenXAppTests.ComposerPreferences.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
