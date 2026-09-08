import Foundation
import Testing
@testable import TenXApp

@MainActor
@Test func sessionMapPreferencesDefaultToSmolAndCheckerOff() throws {
    let suite = "TenXAppTests.SessionMapPreferences.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    let preferences = SessionMapPreferenceStore(defaults: defaults)

    #expect(preferences.writerSelection == .role("smol"))
    #expect(preferences.checkerSelection == nil)
    #expect(preferences.isUnattendedGenerationEnabled)
}

@MainActor
@Test func sessionMapPreferencesPersistAcrossReloads() throws {
    let suite = "TenXAppTests.SessionMapPreferences.Reload.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = SessionMapPreferenceStore(defaults: defaults)

    preferences.writerSelection = .model(id: "provider/writer", effort: "high")
    preferences.checkerSelection = .role("vision")
    preferences.isUnattendedGenerationEnabled = false

    let reloaded = SessionMapPreferenceStore(defaults: defaults)
    #expect(reloaded.writerSelection == .model(id: "provider/writer", effort: "high"))
    #expect(reloaded.checkerSelection == .role("vision"))
    #expect(!reloaded.isUnattendedGenerationEnabled)
}
