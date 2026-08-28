import Foundation
import OmpKit
import Testing
@testable import TenXApp

private func snapshot(_ json: String) throws -> OmpUsageSnapshot {
    try JSONDecoder().decode(OmpUsageSnapshot.self, from: Data(json.utf8))
}

@Suite struct ProviderAccountUsageBackendTests {

@Test func accountsAreDerivedPerReportInStableOrder() throws {
    let parsed = try snapshot("""
    {"generatedAt":1,"reports":[
      {"provider":"anthropic","fetchedAt":1,"limits":[],"metadata":{"email":"work@example.com","accountId":"acc-2"}},
      {"provider":"anthropic","fetchedAt":1,"limits":[],"metadata":{"email":"home@example.com","accountId":"acc-1"}}
    ],"accountsWithoutUsage":[],"disabledCredentials":[]}
    """)

    let accounts = ProviderAccountUsageBackend.accounts(from: parsed, providerID: "anthropic")

    #expect(accounts.map(\.displayLabel) == ["work@example.com", "home@example.com"])
    #expect(accounts.map(\.connectionOrder) == [0, 1])
    #expect(accounts[0].accountRef == ProviderAccountRef.make(
        providerID: "anthropic", accountID: "acc-2", email: "work@example.com", orgID: nil, projectID: nil))
    #expect(accounts.allSatisfy { $0.availability == .available })
}

@Test func connectionOrderIsScopedToTheProvidersOwnReports() throws {
    // A bug that indexes into the whole `reports` array (rather than that
    // provider's own filtered reports) would pass every other fixture in
    // this file, since they're all single-provider. This interleaves a
    // second provider's report between two anthropic ones: a whole-array
    // index would give the second anthropic account connectionOrder 2, not 1.
    let parsed = try snapshot("""
    {"generatedAt":1,"reports":[
      {"provider":"anthropic","fetchedAt":1,"limits":[],"metadata":{"email":"first@example.com","accountId":"acc-1"}},
      {"provider":"openai-codex","fetchedAt":1,"limits":[],"metadata":{"email":"codex@example.com","accountId":"acc-codex"}},
      {"provider":"anthropic","fetchedAt":1,"limits":[],"metadata":{"email":"second@example.com","accountId":"acc-2"}}
    ],"accountsWithoutUsage":[],"disabledCredentials":[]}
    """)

    let accounts = ProviderAccountUsageBackend.accounts(from: parsed, providerID: "anthropic")

    #expect(accounts.map(\.displayLabel) == ["first@example.com", "second@example.com"])
    #expect(accounts.map(\.connectionOrder) == [0, 1])
}

@Test func duplicateLabelsAreDistinguishedByDetailLabel() throws {
    let parsed = try snapshot("""
    {"generatedAt":1,"reports":[
      {"provider":"anthropic","fetchedAt":1,"limits":[],"metadata":{"email":"same@example.com","accountId":"acc-1","orgName":"Personal"}},
      {"provider":"anthropic","fetchedAt":1,"limits":[],"metadata":{"email":"same@example.com","accountId":"acc-2","orgName":"Work"}}
    ],"accountsWithoutUsage":[],"disabledCredentials":[]}
    """)

    let accounts = ProviderAccountUsageBackend.accounts(from: parsed, providerID: "anthropic")

    #expect(accounts.map(\.detailLabel) == ["Personal", "Work"])
    #expect(accounts[0].accountRef != accounts[1].accountRef)
}

@Test func disabledCredentialsMarkAccountsUnavailable() throws {
    // Brief's fixture used `reason`, but `OmpDisabledCredential` decodes
    // `cause` (non-optional), alongside non-optional `id`, `type`, and
    // `disabledAtMs` — see App/Providers/ProviderUsageSnapshot.swift and
    // stock OMP's `DisabledCredentialSummary` (packages/ai/src/auth-storage.ts,
    // commit b4e8e856a). Corrected to a fixture that actually decodes; Step 3's
    // match rule (provider + accountId) is unaffected by the filler fields.
    let parsed = try snapshot("""
    {"generatedAt":1,"reports":[
      {"provider":"anthropic","fetchedAt":1,"limits":[],"metadata":{"email":"a@example.com","accountId":"acc-1"}}
    ],"accountsWithoutUsage":[],"disabledCredentials":[
      {"id":1,"provider":"anthropic","type":"oauth","cause":"quota","accountId":"acc-1","disabledAtMs":1}
    ]}
    """)

    let accounts = ProviderAccountUsageBackend.accounts(from: parsed, providerID: "anthropic")

    #expect(accounts.map(\.availability) == [.unavailable])
}

@Test func reportsWithoutAnAccountKeyAreSkipped() throws {
    let parsed = try snapshot("""
    {"generatedAt":1,"reports":[
      {"provider":"cursor","fetchedAt":1,"limits":[],"metadata":{}}
    ],"accountsWithoutUsage":[],"disabledCredentials":[]}
    """)

    #expect(ProviderAccountUsageBackend.accounts(from: parsed, providerID: "cursor").isEmpty)
}

@Test func usageMapsLimitsWithMillisecondTimestampsAndSourceIndex() throws {
    let parsed = try snapshot("""
    {"generatedAt":1,"reports":[
      {"provider":"anthropic","fetchedAt":2000,"limits":[
        {"id":"5h","label":"5 Hour","scope":{"provider":"anthropic"},"window":{"id":"5h","label":"5 Hour","resetsAt":5000},"amount":{"remainingFraction":0.75,"unit":"percent"},"status":"ok"},
        {"id":"7d","label":"7 Day","scope":{"provider":"anthropic"},"amount":{"unit":"percent"},"status":"warning"}
      ],"metadata":{"email":"a@example.com","accountId":"acc-1"}}
    ],"accountsWithoutUsage":[],"disabledCredentials":[]}
    """)

    let usage = ProviderAccountUsageBackend.usage(from: parsed, providerID: "anthropic")

    #expect(usage.count == 1)
    let entry = try #require(usage.first)
    #expect(entry.accountRef == ProviderAccountRef.make(
        providerID: "anthropic", accountID: "acc-1", email: "a@example.com", orgID: nil, projectID: nil))
    #expect(entry.refreshedAt == Date(timeIntervalSince1970: 2))
    #expect(entry.usageWindows.map(\.id) == ["5h", "7d"])
    #expect(entry.usageWindows.map(\.sourceIndex) == [0, 1])
    #expect(entry.usageWindows[0].remainingFraction == 0.75)
    #expect(entry.usageWindows[0].resetsAt == Date(timeIntervalSince1970: 5))
    #expect(entry.usageWindows[0].status == "ok")
    #expect(entry.usageWindows[1].remainingFraction == nil)
    #expect(entry.usageWindows[1].resetsAt == nil)
    #expect(entry.usageWindows[1].status == "warning")
}

@Test func usageSkipsReportsWithoutAnAccountKey() throws {
    let parsed = try snapshot("""
    {"generatedAt":1,"reports":[
      {"provider":"cursor","fetchedAt":1,"limits":[],"metadata":{}}
    ],"accountsWithoutUsage":[],"disabledCredentials":[]}
    """)

    #expect(ProviderAccountUsageBackend.usage(from: parsed, providerID: "cursor").isEmpty)
}

}
