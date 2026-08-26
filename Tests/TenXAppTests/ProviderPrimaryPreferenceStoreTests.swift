import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Suite struct ProviderPrimaryPreferenceStoreTests {
    @Test func missingPrimaryRepairsToFirstEligibleConnectionOrder() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let replacement = store.repairPrimary(
            providerID: "openai-codex",
            accounts: [
                account(ref: "acct_A", order: 0, availability: .unavailable),
                account(ref: "acct_B", order: 1, availability: .available),
            ])

        #expect(replacement == "acct_B")
        #expect(store.primaryAccountRef(providerID: "openai-codex") == "acct_B")
    }

    @Test func existingEligiblePrimaryIsRetained() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.setPrimaryAccountRef("acct_B", providerID: "openai-codex")
        let replacement = store.repairPrimary(
            providerID: "openai-codex",
            accounts: [
                account(ref: "acct_A", order: 0, availability: .available),
                account(ref: "acct_B", order: 1, availability: .limited),
            ])

        #expect(replacement == "acct_B")
        #expect(store.primaryAccountRef(providerID: "openai-codex") == "acct_B")
    }

    @Test func noEligibleAccountClearsPrimary() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.setPrimaryAccountRef("acct_A", providerID: "openai-codex")
        let replacement = store.repairPrimary(
            providerID: "openai-codex",
            accounts: [
                account(ref: "acct_A", order: 0, availability: .unavailable),
                account(ref: "acct_B", order: 1, availability: .unavailable),
            ])

        #expect(replacement == nil)
        #expect(store.primaryAccountRef(providerID: "openai-codex") == nil)
    }

    @Test func repairSerializesOnlyProviderAndAccountRefs() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        _ = store.repairPrimary(
            providerID: "openai-codex",
            accounts: [
                account(ref: "acct_B", order: 1, availability: .available),
            ])

        let domain = try #require(defaults.persistentDomain(forName: suiteName))
        #expect(Set(domain.keys) == ["providerPrimaryAccountRefs.v1"])
        #expect(defaults.dictionary(forKey: "providerPrimaryAccountRefs.v1") as? [String: String] == [
            "openai-codex": "acct_B",
        ])
    }
}

private func makeStore() throws -> (
    store: ProviderPrimaryPreferenceStore,
    defaults: UserDefaults,
    suiteName: String
) {
    let suiteName = "TenXAppTests.ProviderPrimary.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return (ProviderPrimaryPreferenceStore(defaults: defaults), defaults, suiteName)
}

private func account(
    ref: String,
    order: Int,
    availability: ProviderAccountAvailability
) -> ProviderAccountSummary {
    ProviderAccountSummary(
        providerID: "openai-codex",
        accountRef: ref,
        displayLabel: "Account \(ref)",
        detailLabel: "Do not persist",
        connectionOrder: order,
        availability: availability,
        isActiveForSession: true)
}
