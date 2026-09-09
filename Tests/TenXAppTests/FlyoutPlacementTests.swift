import Foundation
import Testing
@testable import TenXApp

@Test func flyoutPlacementUsesPreferredAboveWhenBodyFits() {
    let placement = FlyoutPlacement.resolve(
        triggerFrame: CGRect(x: 100, y: 500, width: 120, height: 28),
        desiredPanelSize: CGSize(width: 440, height: 300),
        usableBounds: CGRect(x: 0, y: 0, width: 760, height: 560),
        preferredDirection: .above)

    #expect(placement.direction == .above)
    #expect(placement.panelFrame == CGRect(x: 100, y: 200, width: 440, height: 300))
    #expect(placement.triggerOffsetX == 0)
}

@Test func flyoutPlacementFlipsBelowWhenPreferredAboveDoesNotFit() {
    let placement = FlyoutPlacement.resolve(
        triggerFrame: CGRect(x: 100, y: 20, width: 120, height: 28),
        desiredPanelSize: CGSize(width: 440, height: 300),
        usableBounds: CGRect(x: 0, y: 0, width: 760, height: 560),
        preferredDirection: .above)

    #expect(placement.direction == .below)
    #expect(placement.panelFrame == CGRect(x: 100, y: 48, width: 440, height: 300))
    #expect(placement.triggerOffsetX == 0)
}

@Test func flyoutPlacementClampsRightEdgeAndKeepsTriggerConnection() {
    let placement = FlyoutPlacement.resolve(
        triggerFrame: CGRect(x: 700, y: 500, width: 52, height: 28),
        desiredPanelSize: CGSize(width: 440, height: 300),
        usableBounds: CGRect(x: 0, y: 0, width: 760, height: 560),
        preferredDirection: .above)

    #expect(placement.panelFrame == CGRect(x: 312, y: 200, width: 440, height: 300))
    #expect(placement.triggerOffsetX == 388)
    #expect(placement.triggerOffsetX + 52 == placement.panelFrame.width)
}

@Test func flyoutPlacementClampsOversizedWidthToUsableBounds() {
    let placement = FlyoutPlacement.resolve(
        triggerFrame: CGRect(x: 250, y: 500, width: 50, height: 28),
        desiredPanelSize: CGSize(width: 440, height: 300),
        usableBounds: CGRect(x: 0, y: 0, width: 320, height: 560),
        preferredDirection: .above)

    #expect(placement.panelFrame == CGRect(x: 8, y: 200, width: 304, height: 300))
    #expect(placement.triggerOffsetX == 242)
}

@Test func flyoutPlacementUsesLargerSideAndLimitsBodyHeightInShortWindow() {
    let placement = FlyoutPlacement.resolve(
        triggerFrame: CGRect(x: 100, y: 90, width: 120, height: 28),
        desiredPanelSize: CGSize(width: 440, height: 400),
        usableBounds: CGRect(x: 0, y: 0, width: 760, height: 200),
        preferredDirection: .below)

    #expect(placement.direction == .above)
    #expect(placement.panelFrame == CGRect(x: 100, y: 8, width: 440, height: 82))
    #expect(placement.isHeightConstrained)
}
