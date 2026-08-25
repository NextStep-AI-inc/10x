import Testing
@testable import TenXApp

@MainActor
@Test func searchPresentationNeverChangesTheCurrentRoute() {
    let model = AppModel()
    model.route = .session("/tmp/a")

    model.openSearch()
    #expect(model.isSearchPresented)
    #expect(model.route == .session("/tmp/a"))

    model.closeSearch()
    #expect(!model.isSearchPresented)
    #expect(model.route == .session("/tmp/a"))
}
