import Foundation
import Testing
@testable import TenXApp

@Test func usagePresentationShowsRemainingCapacityAndOmitsUnboundedRailAmounts() throws {
    let snapshot = try usageSnapshotFixture()
    let presentation = ProviderUsagePresentation.make(
        snapshot: snapshot,
        providerNames: ["cursor": "Cursor"],
        now: Date(timeIntervalSince1970: 1_787_675_746))

    let account = try #require(presentation.providers.first?.accounts.first)
    #expect(account.label == "tanner@example.com")
    #expect(account.limits[0].percentage == 50)
    #expect(account.limits[0].tone == .standard)
    #expect(account.amounts == [ProviderUsageAmount(
        id: "cursor:requests", label: "Requests", value: 4, unit: "requests")])
    #expect(presentation.dockProviders[0].accounts[0].limits.map(\.label) == ["Cursor Models"])
}

@Test func usagePresentationOrdersKnownDurationLimitsAroundUnknownSourceSlots() throws {
    let presentation = ProviderUsagePresentation.make(
        snapshot: try usageSnapshot(limits: [
            usageLimit(id: "weekly", label: "Weekly", windowID: "weekly"),
            usageLimit(id: "unknown-a", label: "Unknown A", windowID: "rolling"),
            usageLimit(id: "five-hour", label: "5 hour", windowID: "5-hour"),
            usageLimit(id: "daily", label: "Daily", windowID: "daily"),
            usageLimit(id: "unknown-b", label: "Unknown B", windowID: "custom"),
        ]),
        providerNames: ["cursor": "Cursor"],
        now: Date(timeIntervalSince1970: 1))

    let provider = try #require(presentation.dockProviders.first)
    #expect(provider.ringLimits.map(\.label) == [
        "5 hour",
        "Unknown A",
        "Daily",
        "Weekly",
        "Unknown B",
    ])
}

@Test func usagePresentationRetainsSourceOrderForEqualAndUnknownDurationLimitsAcrossAccounts() throws {
    let presentation = ProviderUsagePresentation.make(
        snapshot: try usageSnapshot(reports: [
            usageReport(limits: [
                usageLimit(id: "daily-a", label: "Daily A", windowID: "daily"),
                usageLimit(id: "unknown-a", label: "Unknown A", windowID: "rolling"),
                usageLimit(id: "daily-b", label: "Daily B", windowID: "daily"),
            ]),
            usageReport(limits: [
                usageLimit(id: "unknown-b", label: "Unknown B", windowID: "custom"),
                usageLimit(id: "weekly", label: "Weekly", windowID: "weekly"),
            ]),
        ]),
        providerNames: ["cursor": "Cursor"],
        now: Date(timeIntervalSince1970: 1))

    let provider = try #require(presentation.dockProviders.first)
    #expect(provider.ringLimits.map(\.label) == [
        "Daily A",
        "Unknown A",
        "Daily B",
        "Unknown B",
        "Weekly",
    ])
    #expect(provider.ringLimits.count == 5)
}

@Test func providerUsageAbbreviationsUseKnownMappingsAndDeterministicFallbacks() {
    #expect(ProviderUsageProvider(id: "anthropic", name: "Anthropic", accounts: []).abbreviation == "ANT")
    #expect(ProviderUsageProvider(id: "openai-codex", name: "ChatGPT", accounts: []).abbreviation == "OAI")
    #expect(ProviderUsageProvider(id: "cursor", name: "Cursor", accounts: []).abbreviation == "CUR")
    #expect(ProviderUsageProvider(id: "google-gemini-cli", name: "Google Cloud Code Assist", accounts: []).abbreviation == "GCA")
    #expect(ProviderUsageProvider(id: "github-copilot", name: "GitHub Copilot", accounts: []).abbreviation == "GHC")
    #expect(ProviderUsageProvider(id: "github-copilot", name: "GitLab Copilot", accounts: []).abbreviation == "GLC")
    #expect(ProviderUsageProvider(id: "deepseek", name: "DeepSeek", accounts: []).abbreviation == "DEE")
    #expect(ProviderUsageProvider(id: "unicode", name: "ßXX", accounts: []).abbreviation == "SSX")
    #expect(ProviderUsageProvider(id: "unicode", name: "ßXX", accounts: []).abbreviation.count == 3)
    #expect(ProviderUsageProvider(id: "x", name: "X", accounts: []).abbreviation.count == 3)
}

@Test func remainingCapacityClampsAndUsesAttentionTones() {
    #expect(ProviderUsageLimit.remainingPercentage(usedFraction: -0.2) == 100)
    #expect(ProviderUsageLimit.remainingPercentage(usedFraction: 0.82) == 18)
    #expect(ProviderUsageLimit.remainingPercentage(usedFraction: 1.4) == 0)
}

@Test func providerUsageNormalizesPercentagesForRendering() {
    let over = ProviderUsageLimit(id: "over", label: "Weekly", percentage: 140, resetWindow: "Mon")
    let under = ProviderUsageLimit(id: "under", label: "Spark", percentage: -8, resetWindow: "Thu")

    #expect(over.normalizedFraction == 1)
    #expect(under.normalizedFraction == 0)
}

@Test func providerUsageToneMakesOnlyLowAndExhaustedLimitsAttentionStates() {
    let healthy = ProviderUsageLimit(id: "healthy", label: "5 hours", percentage: 64, resetWindow: "2h 14m")
    let low = ProviderUsageLimit(id: "low", label: "Spark", percentage: 18, resetWindow: "Thu")
    let exhausted = ProviderUsageLimit(id: "empty", label: "Weekly", percentage: 0, resetWindow: "Mon")

    #expect(healthy.tone == .standard)
    #expect(low.tone == .warning)
    #expect(exhausted.tone == .exhausted)
}

@Test func anthropicRailUsageUsesCompanyAndShortWindowNames() throws {
    let snapshot = try JSONDecoder().decode(OmpUsageSnapshot.self, from: Data(#"""
    {
      "generatedAt":1,
      "reports":[{
        "provider":"anthropic",
        "fetchedAt":1,
        "limits":[
          {"id":"five-hour","label":"Claude 5 Hour","scope":{"provider":"anthropic"},"amount":{"remainingFraction":0.98,"unit":"percent"}},
          {"id":"weekly","label":"Claude 7 Day","scope":{"provider":"anthropic"},"amount":{"remainingFraction":0.5,"unit":"percent"}},
          {"id":"fable","label":"Claude 7 Day (Fable)","scope":{"provider":"anthropic"},"amount":{"remainingFraction":0.14,"unit":"percent"}}
        ]
      }],
      "accountsWithoutUsage":[],
      "disabledCredentials":[]
    }
    """#.utf8))

    let presentation = ProviderUsagePresentation.make(
        snapshot: snapshot,
        providerNames: ["anthropic": "Anthropic (Claude Pro/Max)"],
        now: Date(timeIntervalSince1970: 1))
    let provider = try #require(presentation.railProviders.first)

    #expect(provider.name == "Anthropic")
    #expect(provider.limits.map(\.label) == ["5 hour", "Weekly", "Fable"])
}

@Test func usagePresentationUsesEveryIdentityFieldToDistinguishAccounts() throws {
    let snapshot = try JSONDecoder().decode(OmpUsageSnapshot.self, from: Data(#"""
    {
      "generatedAt":1,
      "reports":[
        {"provider":"cursor","fetchedAt":1,"limits":[{"id":"a","label":"Models","scope":{"provider":"cursor"},"amount":{"remainingFraction":0.5,"unit":"percent"}}],"metadata":{"email":"team@example.com","accountId":"team","projectId":"project","orgId":"org-a","orgName":"Design"}},
        {"provider":"cursor","fetchedAt":1,"limits":[{"id":"b","label":"Models","scope":{"provider":"cursor"},"amount":{"remainingFraction":0.5,"unit":"percent"}}],"metadata":{"email":"team@example.com","accountId":"team","projectId":"project","orgId":"org-b","orgName":"Engineering"}},
        {"provider":"cursor","fetchedAt":1,"limits":[{"id":"c","label":"Models","scope":{"provider":"cursor"},"amount":{"remainingFraction":0.5,"unit":"percent"}}],"metadata":{"email":"team@example.com","accountId":"team","projectId":"project","enterpriseUrl":"https://enterprise.example.com"}}
      ],
      "accountsWithoutUsage":[],
      "disabledCredentials":[]
    }
    """#.utf8))

    let presentation = ProviderUsagePresentation.make(
        snapshot: snapshot,
        providerNames: ["cursor": "Cursor"],
        now: Date(timeIntervalSince1970: 1))
    let accounts = try #require(presentation.providers.first?.accounts)

    #expect(Set(accounts.map(\.id)).count == 3)
    #expect(accounts.map(\.label) == [
        "team@example.com (Design)",
        "team@example.com (Engineering)",
        "team@example.com (https://enterprise.example.com)",
    ])
}

@Test func remainingFractionUsesTheDocumentedPrecedenceAndClamps() throws {
    let cases = [
        ("explicit remaining", #"{"remainingFraction":0.25,"usedFraction":0.1,"used":1,"limit":10,"unit":"percent"}"#, 25),
        ("used fraction", #"{"usedFraction":0.25,"unit":"percent"}"#, 75),
        ("used and limit", #"{"used":25,"limit":100,"unit":"requests"}"#, 75),
        ("percent fallback", #"{"used":25,"unit":"percent"}"#, 75),
        ("high clamp", #"{"remainingFraction":1.25,"unit":"percent"}"#, 100),
        ("low clamp", #"{"usedFraction":1.25,"unit":"percent"}"#, 0),
    ]

    for testCase in cases {
        let snapshot = try usageSnapshot(amount: testCase.1)
        let presentation = ProviderUsagePresentation.make(
            snapshot: snapshot,
            providerNames: ["cursor": "Cursor"],
            now: Date(timeIntervalSince1970: 1))
        let percentage = try #require(presentation.providers.first?.accounts.first?.limits.first?.percentage)

        #expect(percentage == testCase.2, "\(testCase.0) should retain \(testCase.2) percent")
    }
}

@Test func usageDetailGroupsEveryAccountStateUnderOneProvider() {
    let identity = ProviderUsageAccountIdentity(
        email: "team@example.com",
        accountID: nil,
        projectID: nil,
        enterpriseURL: nil,
        orgID: nil,
        orgName: nil)
    let usage = ProviderUsagePresentation(
        providers: [ProviderUsageProvider(
            id: "anthropic",
            name: "Anthropic",
            accounts: [ProviderUsageAccount(
                id: "anthropic:team@example.com",
                label: "team@example.com",
                identity: identity,
                limits: [],
                amounts: [],
                notes: [],
                isUsageAvailable: true)])],
        accountsWithoutUsage: [ProviderUsageAccount(
            id: "anthropic:work@example.com",
            label: "work@example.com",
            identity: identity,
            limits: [],
            amounts: [],
            notes: [],
            isUsageAvailable: false)],
        credentialIssues: [ProviderCredentialIssue(
            id: "anthropic:2",
            providerID: "anthropic",
            providerName: "Anthropic",
            label: "old@example.com",
            type: "oauth",
            disabledAt: Date(timeIntervalSince1970: 0))])

    let groups = ProviderUsageDetailGroup.make(
        usage: usage,
        providers: [ProviderLoginProvider(
            id: "anthropic", name: "Anthropic", isAvailable: true, isAuthenticated: true)])

    #expect(groups.count == 1)
    #expect(groups[0].providerID == "anthropic")
    #expect(groups[0].accounts.map(\.label) == ["team@example.com", "work@example.com"])
    #expect(groups[0].credentialIssues.map(\.id) == ["anthropic:2"])
}

private func usageSnapshot(amount: String) throws -> OmpUsageSnapshot {
    try JSONDecoder().decode(OmpUsageSnapshot.self, from: Data("""
    {
      "generatedAt":1,
      "reports":[{
        "provider":"cursor",
        "fetchedAt":1,
        "limits":[{
          "id":"cursor:limit",
          "label":"Models",
          "scope":{"provider":"cursor"},
          "amount":\(amount)
        }]
      }],
      "accountsWithoutUsage":[],
      "disabledCredentials":[]
    }
    """.utf8))
}

private func usageSnapshot(limits: [String]) throws -> OmpUsageSnapshot {
    try usageSnapshot(reports: [usageReport(limits: limits)])
}

private func usageSnapshot(reports: [String]) throws -> OmpUsageSnapshot {
    try JSONDecoder().decode(OmpUsageSnapshot.self, from: Data("""
    {
      "generatedAt":1,
      "reports":[\(reports.joined(separator: ","))],
      "accountsWithoutUsage":[],
      "disabledCredentials":[]
    }
    """.utf8))
}

private func usageReport(limits: [String]) -> String {
    #"{"provider":"cursor","fetchedAt":1,"limits":[$LIMITS]}"#
        .replacingOccurrences(of: "$LIMITS", with: limits.joined(separator: ","))
}

private func usageLimit(id: String, label: String, windowID: String) -> String {
    #"{"id":"$ID","label":"$LABEL","scope":{"provider":"cursor","windowId":"$WINDOW"},"window":{"id":"$WINDOW","label":"$LABEL"},"amount":{"remainingFraction":0.5,"unit":"percent"}}"#
        .replacingOccurrences(of: "$ID", with: id)
        .replacingOccurrences(of: "$LABEL", with: label)
        .replacingOccurrences(of: "$WINDOW", with: windowID)
}
