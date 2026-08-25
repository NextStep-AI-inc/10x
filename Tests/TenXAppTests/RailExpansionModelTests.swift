import Testing
@testable import TenXApp

@MainActor
@Test func railCollapsesAfterGracePeriod() async throws {
    let model = RailExpansionModel(collapseDelay: .milliseconds(300))

    model.pointerEntered()
    model.pointerExited()
    try await Task.sleep(for: .milliseconds(150))
    #expect(model.isExpanded)

    try await Task.sleep(for: .milliseconds(200))
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
