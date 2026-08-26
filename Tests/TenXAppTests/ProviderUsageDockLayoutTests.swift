import Testing
@testable import TenXApp

@Suite struct ProviderUsageDockLayoutTests {
@Test func usageDockUsesRegularWheelsBesideComposerWhenGutterFitsThreeProviders() {
    let layout = ProviderUsageDockLayout.compact(
        shellWidth: 1280,
        contentLeadingInset: 64,
        stackWidths: [54, 54, 54],
        hasComposer: true)

    #expect(layout == ProviderUsageDockCompactLayout(
        wheelDiameter: 54,
        trailingOffset: 0,
        bottomOffset: 12))
}

@Test func usageDockUsesConstrainedWheelsAboveComposerWhenGutterDoesNotFitThreeProviders() {
    let layout = ProviderUsageDockLayout.compact(
        shellWidth: 760,
        contentLeadingInset: 64,
        stackWidths: [54, 54, 54],
        hasComposer: true)

    #expect(layout == ProviderUsageDockCompactLayout(
        wheelDiameter: 44,
        trailingOffset: 26,
        bottomOffset: 116))
}

@Test func completeAccountStackWidthsControlWidePlacementDecision() {
    let singleAccountStacks = ProviderUsageDockLayout.compact(
        shellWidth: 1180,
        contentLeadingInset: 64,
        stackWidths: [54, 54],
        hasComposer: true)
    let multiAccountStacks = ProviderUsageDockLayout.compact(
        shellWidth: 1180,
        contentLeadingInset: 64,
        stackWidths: [82, 82],
        hasComposer: true)

    #expect(singleAccountStacks.wheelDiameter == 54)
    #expect(multiAccountStacks.wheelDiameter == 44)
}

@Test func accountStackWidthsNeverChangeComposerDerivedOffsets() {
    let compact = ProviderUsageDockLayout.compact(
        shellWidth: 760,
        contentLeadingInset: 64,
        stackWidths: [54],
        hasComposer: true)
    let expanded = ProviderUsageDockLayout.compact(
        shellWidth: 760,
        contentLeadingInset: 64,
        stackWidths: [120, 120, 120],
        hasComposer: true)

    #expect(compact.trailingOffset == expanded.trailingOffset)
    #expect(compact.bottomOffset == expanded.bottomOffset)
}

@Test func usageDockStandaloneRoutesKeepRegularWheelsWithoutOffsets() {
    let layout = ProviderUsageDockLayout.compact(
        shellWidth: 760,
        contentLeadingInset: 64,
        stackWidths: [54, 54, 54],
        hasComposer: false)

    #expect(layout == .standalone)
}

@Test func accountStacksWidenTheGroupUsedForPlacement() {
    let singleAccount = ProviderUsageDockLayout.stackWidths(providers: [
        dockLayoutProvider(id: "anthropic", accountIDs: ["a"]),
    ])
    let threeAccounts = ProviderUsageDockLayout.stackWidths(providers: [
        dockLayoutProvider(id: "anthropic", accountIDs: ["a", "b", "c"]),
    ])

    #expect(singleAccount == [ProviderUsageDockLayout.regular54])
    #expect(threeAccounts.count == 1)
    #expect(threeAccounts[0] > singleAccount[0])
}

@Test func providerOnlyEntriesMeasureAsOneWheel() {
    let widths = ProviderUsageDockLayout.stackWidths(providers: [
        dockLayoutProvider(id: "cursor", accountIDs: [], capability: .providerOnly),
        dockLayoutProvider(id: "anthropic", accountIDs: ["a", "b"], capability: .providerOnly),
    ])

    #expect(widths == [ProviderUsageDockLayout.regular54, ProviderUsageDockLayout.regular54])
}

@Test func derivedStackWidthsDriveTheConstrainedPlacement() {
    let providers = [
        dockLayoutProvider(id: "anthropic", accountIDs: ["a", "b", "c"]),
        dockLayoutProvider(id: "openai-codex", accountIDs: ["d", "e", "f"]),
    ]
    let derived = ProviderUsageDockLayout.compact(
        shellWidth: 1180,
        contentLeadingInset: 64,
        stackWidths: ProviderUsageDockLayout.stackWidths(providers: providers),
        hasComposer: true)
    let providerOnly = ProviderUsageDockLayout.compact(
        shellWidth: 1180,
        contentLeadingInset: 64,
        providerCount: providers.count,
        hasComposer: true)

    #expect(providerOnly.wheelDiameter == ProviderUsageDockLayout.regular54)
    #expect(derived.wheelDiameter == ProviderUsageDockLayout.constrained44)
}

private func dockLayoutProvider(
    id: String,
    accountIDs: [String],
    capability: ProviderAccountCapability = .accountRouting
) -> ProviderUsageProvider {
    ProviderUsageProvider(
        id: id,
        name: id,
        accounts: accountIDs.map { accountID in
            ProviderUsageAccount(
                id: "\(id):\(accountID)",
                label: accountID,
                identity: .empty,
                limits: [],
                amounts: [],
                notes: [],
                isUsageAvailable: true,
                accountRef: accountID)
        },
        capability: capability,
        foregroundAccountRef: accountIDs.first)
}
}
