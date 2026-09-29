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

@Test func narrowDockMovesProviderGroupAboveWithoutCoveringEditor() {
    #expect(ProviderUsageDockLayout.placement(
        availableWidth: 760, factsMinWidth: 380, actionsMinWidth: 200,
        providerWidth: 148) == .aboveLine)
    #expect(ProviderUsageDockLayout.placement(
        availableWidth: 1280, factsMinWidth: 380, actionsMinWidth: 200,
        providerWidth: 148) == .belowLine)
}

@Test func minimumWidthPreservesSendStatusAndWheelHitTargets() {
    #expect(ProviderUsageDockLayout.placement(
        availableWidth: 760, factsMinWidth: 380, actionsMinWidth: 200,
        providerWidth: 148) == .aboveLine)
    #expect(ProviderUsageDockWheelHoverGeometry(restingDiameter: 28).hitTargetDiameter >= 44)
}

@Test func narrowDockReservesAttachmentStripAboveEditor() {
    let withoutAttachments = ProviderUsageDockLayout.aboveLineBottomOffset(hasAttachments: false)
    let withAttachments = ProviderUsageDockLayout.aboveLineBottomOffset(hasAttachments: true)
    #expect(withoutAttachments == 168)
    #expect(withAttachments >= withoutAttachments + ComposerAttachmentsView.stripHeight)
}

@Test func noProvidersReserveNoFooterSpace() {
    #expect(ProviderUsageDockLayout.footerWidth(providers: []) == 0)
}
}
