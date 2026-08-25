import Testing
@testable import TenXApp

@MainActor
@Test func contentInsetTracksRailExpansion() {
    let model = RailExpansionModel()

    #expect(model.contentLeadingInset == 64)
    model.pointerEntered()
    #expect(model.contentLeadingInset == 220)
}

@Test func railTransitionDisablesAnimationWhenReduceMotionIsEnabled() {
    #expect(RailExpansionTransition.animationDuration(reduceMotion: false) == 0.2)
    #expect(RailExpansionTransition.animationDuration(reduceMotion: true) == nil)
}

@MainActor
@Test func railCollapsesAfterGracePeriod() async throws {
    let model = RailExpansionModel(collapseDelay: .milliseconds(300))

    model.pointerEntered()
    model.pointerExited()
    try await Task.sleep(for: .milliseconds(150))
    #expect(model.isExpanded)

    let deadline = ContinuousClock.now + .seconds(2)
    while model.isExpanded && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(!model.isExpanded)
}

@MainActor
@Test func reenteringRailCancelsPendingCollapse() async throws {
    let model = RailExpansionModel(collapseDelay: .milliseconds(300))

    model.pointerEntered()
    model.pointerExited()
    try await Task.sleep(for: .milliseconds(150))
    model.pointerEntered()
    try await Task.sleep(for: .milliseconds(200))

    #expect(model.isExpanded)
}

@MainActor
@Test func keyboardFocusKeepsRailExpanded() async throws {
    let model = RailExpansionModel(collapseDelay: .milliseconds(40))

    model.focusChanged(true)
    model.pointerExited()
    try await Task.sleep(for: .milliseconds(80))

    #expect(model.isExpanded)
}
