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

@Test func usageDockTracksTheReservedFooterSlotWhenTheComposerMoves() {
    let layout = ProviderUsageDockLayout.compact(
        shellSize: CGSize(width: 900, height: 700),
        footerFrame: CGRect(x: 620, y: 570, width: 148, height: 60))
    #expect(layout.wheelDiameter == 28)
    #expect(layout.trailingOffset + 16 == CGFloat(132))
    #expect(layout.bottomOffset + 16 == CGFloat(70))
}

@Test func noProvidersReserveNoFooterSpace() {
    #expect(ProviderUsageDockLayout.footerWidth(providers: []) == 0)
}
}
