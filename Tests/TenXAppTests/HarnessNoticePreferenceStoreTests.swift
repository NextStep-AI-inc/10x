import Foundation
import Testing
@testable import TenXApp

@MainActor @Test func harnessNoticePreferencesDefaultToOff() {
    let suiteName = "harness-notice-defaults-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = HarnessNoticePreferenceStore(defaults: defaults)

    #expect(!store.isEnabled)
    #expect(store.threshold == 0)
    #expect(store.modelOverride == nil)
}

@MainActor @Test func harnessNoticePreferencesPersistAcrossInstances() {
    let suiteName = "harness-notice-persist-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = HarnessNoticePreferenceStore(defaults: defaults)
    store.isEnabled = true
    store.threshold = 1_000
    store.modelOverride = "cursor/composer-2.5-fast"

    let reloaded = HarnessNoticePreferenceStore(defaults: defaults)
    #expect(reloaded.isEnabled)
    #expect(reloaded.threshold == 1_000)
    #expect(reloaded.modelOverride == "cursor/composer-2.5-fast")
}
