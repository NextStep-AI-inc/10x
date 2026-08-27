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

@Test func usageDockUsesSendButtonSizedWheelsInsideComposerWhenGutterDoesNotFitThreeProviders() {
    let layout = ProviderUsageDockLayout.compact(
        shellWidth: 760,
        contentLeadingInset: 64,
        providerCount: 3,
        hasComposer: true)

    #expect(layout == ProviderUsageDockCompactLayout(
        wheelDiameter: 28,
        trailingOffset: 68,
        bottomOffset: 22))
}

@Test func usageDockProviderCountControlsWidePlacementDecision() {
    let twoProviderLayout = ProviderUsageDockLayout.compact(
        shellWidth: 1180,
        contentLeadingInset: 64,
        providerCount: 2,
        hasComposer: true)
    let threeProviderLayout = ProviderUsageDockLayout.compact(
        shellWidth: 1180,
        contentLeadingInset: 64,
        providerCount: 3,
        hasComposer: true)

    #expect(twoProviderLayout.wheelDiameter == 54)
    #expect(threeProviderLayout.wheelDiameter == 28)
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
