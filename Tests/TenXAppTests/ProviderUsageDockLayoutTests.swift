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
}
