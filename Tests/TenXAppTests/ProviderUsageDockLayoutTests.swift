import Testing
@testable import TenXApp

@Suite struct ProviderUsageDockLayoutTests {
@Test func usageDockUsesRegularWheelsBesideComposerWhenGutterFitsThreeProviders() {
    let layout = ProviderUsageDockLayout.compact(
        shellWidth: 1280,
        contentLeadingInset: 64,
        providerCount: 3,
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
        providerCount: 3,
        hasComposer: true)

    #expect(layout == ProviderUsageDockCompactLayout(
        wheelDiameter: 44,
        trailingOffset: 26,
        bottomOffset: 116))
}

/// Regression guard for the account-stack redesign: `ProviderAccountStackView`
/// now collapses to one wheel at rest and fans upward on hover instead of
/// spending horizontal space on a rightward cascade, so a multi-account
/// provider measures exactly like a single-account one. 1180 is the exact
/// width the design doc names as where the old cascade used to force the
/// dock above the composer — it must not do that anymore.
@Test func multiAccountProvidersNoLongerWidenTheGutterRequirementAtTheOldConstrainedBoundary() {
    let layout = ProviderUsageDockLayout.compact(
        shellWidth: 1180,
        contentLeadingInset: 64,
        providerCount: 2,
        hasComposer: true)

    #expect(layout.wheelDiameter == ProviderUsageDockLayout.regular54)
}

@Test func usageDockStandaloneRoutesKeepRegularWheelsWithoutOffsets() {
    let layout = ProviderUsageDockLayout.compact(
        shellWidth: 760,
        contentLeadingInset: 64,
        providerCount: 3,
        hasComposer: false)

    #expect(layout == .standalone)
}
}
