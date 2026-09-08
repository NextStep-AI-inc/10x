import Testing
@testable import TenXApp

@Test func railScrollNavigationShowsOnlyAvailableDirections() {
    let top = RailScrollNavigation(offset: 0, contentHeight: 640, viewportHeight: 320)
    #expect(!top.canScrollUp)
    #expect(top.canScrollDown)

    let middle = RailScrollNavigation(offset: 160, contentHeight: 640, viewportHeight: 320)
    #expect(middle.canScrollUp)
    #expect(middle.canScrollDown)

    let bottom = RailScrollNavigation(offset: 320, contentHeight: 640, viewportHeight: 320)
    #expect(bottom.canScrollUp)
    #expect(!bottom.canScrollDown)
}

@Test func railScrollNavigationUsesOnePointBoundaryTolerance() {
    let nearTop = RailScrollNavigation(offset: 1, contentHeight: 640, viewportHeight: 320)
    #expect(!nearTop.canScrollUp)

    let nearBottom = RailScrollNavigation(offset: 319, contentHeight: 640, viewportHeight: 320)
    #expect(!nearBottom.canScrollDown)
}

@Test func railScrollNavigationMovesFourRowsAndClampsToBounds() {
    let middle = RailScrollNavigation(offset: 160, contentHeight: 640, viewportHeight: 320)
    #expect(middle.target(for: .up) == 32)
    #expect(middle.target(for: .down) == 288)

    let nearTop = RailScrollNavigation(offset: 20, contentHeight: 640, viewportHeight: 320)
    #expect(nearTop.target(for: .up) == 0)

    let nearBottom = RailScrollNavigation(offset: 300, contentHeight: 640, viewportHeight: 320)
    #expect(nearBottom.target(for: .down) == 320)
}

@Test func railScrollNavigationExposesItsFixedGeometry() {
    let navigation = RailScrollNavigation(offset: 320, contentHeight: 640, viewportHeight: 320)

    #expect(RailScrollNavigation.rowHeight == 32)
    #expect(RailScrollNavigation.rowsPerStep == 4)
    #expect(RailScrollNavigation.zero
        == RailScrollNavigation(offset: 0, contentHeight: 0, viewportHeight: 0))
    #expect(navigation.maximumOffset == 320)
}
