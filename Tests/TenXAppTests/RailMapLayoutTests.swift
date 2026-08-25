import Testing
@testable import TenXApp

@Suite struct RailMapLayoutTests {
    @Test func shortRailMapUsesItsNaturalHeight() {
        #expect(RailMapLayout.height(itemCount: 4, availableHeight: 500) == 128)
    }

    @Test func overflowingRailMapPreservesEqualMinimumSpacing() {
        #expect(RailMapLayout.minimumVerticalSpacing == 24)
        #expect(RailMapLayout.height(itemCount: 20, availableHeight: 500) == 452)
    }

    @Test func railMapHeightNeverBecomesNegative() {
        #expect(RailMapLayout.height(itemCount: 20, availableHeight: 30) == 0)
    }
}
