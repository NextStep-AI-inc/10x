import CoreGraphics
import Testing
@testable import TenXApp

@Suite struct ProviderUsageDockLayoutTests {
@Test func hoveredProviderWheelEnlargesInsideAStableSemanticTarget() {
    let geometry = ProviderUsageDockWheelHoverGeometry(restingDiameter: 54)

    #expect(geometry.visualScale(isHovered: false) == 1)
    #expect(geometry.visualScale(isHovered: true) > 1)
    #expect(geometry.hitTargetDiameter == 54)
}

@Test func constrainedProviderWheelKeepsItsFortyFourPointHitTargetWhileHovering() {
    let geometry = ProviderUsageDockWheelHoverGeometry(restingDiameter: 28)

    #expect(geometry.hitTargetDiameter == 44)
    #expect(geometry.visualScale(isHovered: true) > geometry.visualScale(isHovered: false))
}

@Test func providerWheelHoverDoesNotAnimateWithReduceMotion() {
    let geometry = ProviderUsageDockWheelHoverGeometry(restingDiameter: 54)

    #expect(geometry.animationDuration(reduceMotion: false) == 0.16)
    #expect(geometry.animationDuration(reduceMotion: true) == nil)
}

@Test func usageDockUsesRegularWheelsBesideComposerWhenGutterFitsThreeProviders() {
    let placement = ProviderUsageDockLayout.placement(
        shellWidth: 1280,
        contentLeadingInset: 64,
        providerCount: 3,
        hasComposer: true)

    #expect(placement == .outsideComposer)
    #expect(ProviderUsageDockCompactLayout.outsideComposer == ProviderUsageDockCompactLayout(
        wheelDiameter: 54,
        trailingOffset: 0,
        bottomOffset: 12))
}

@Test func usageDockUsesReservedFooterSlotWhenGutterDoesNotFitThreeProviders() {
    let placement = ProviderUsageDockLayout.placement(
        shellWidth: 760,
        contentLeadingInset: 64,
        providerCount: 3,
        hasComposer: true)

    #expect(placement == .composerFooter)

    let layout = ProviderUsageDockLayout.compact(
        shellSize: CGSize(width: 900, height: 700),
        footerFrame: CGRect(x: 620, y: 570, width: 148, height: 60))
    #expect(layout.wheelDiameter == 28)
    #expect(layout.trailingOffset + 16 == CGFloat(132))
    #expect(layout.bottomOffset + 16 == CGFloat(70))
}

@Test func usageDockProviderCountControlsWidePlacementDecision() {
    let twoProviders = ProviderUsageDockLayout.placement(
        shellWidth: 1180,
        contentLeadingInset: 64,
        providerCount: 2,
        hasComposer: true)
    let threeProviders = ProviderUsageDockLayout.placement(
        shellWidth: 1180,
        contentLeadingInset: 64,
        providerCount: 3,
        hasComposer: true)

    #expect(twoProviders == .outsideComposer)
    #expect(threeProviders == .composerFooter)
}

@Test func expandedRailCanConsumeTheOutsideDockGutter() {
    let collapsedRail = ProviderUsageDockLayout.placement(
        shellWidth: 1280,
        contentLeadingInset: 64,
        providerCount: 3,
        hasComposer: true)
    let expandedRail = ProviderUsageDockLayout.placement(
        shellWidth: 1280,
        contentLeadingInset: 220,
        providerCount: 3,
        hasComposer: true)

    #expect(collapsedRail == .outsideComposer)
    #expect(expandedRail == .composerFooter)
}

@Test func usageDockStandaloneRoutesKeepRegularWheelsWithoutOffsets() {
    let placement = ProviderUsageDockLayout.placement(
        shellWidth: 760,
        contentLeadingInset: 64,
        providerCount: 3,
        hasComposer: false)

    #expect(placement == .standalone)
    #expect(ProviderUsageDockCompactLayout.standalone == ProviderUsageDockCompactLayout(
        wheelDiameter: 54,
        trailingOffset: 0,
        bottomOffset: 0))
}

@Test func noProvidersReserveNoFooterSpace() {
    #expect(ProviderUsageDockLayout.footerWidth(providers: []) == 0)
}
}
