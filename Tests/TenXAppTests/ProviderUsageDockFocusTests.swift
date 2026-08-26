import Testing
@testable import TenXApp

@Test func providerUsageDockFocusReturnWaitsForCompactMountAndConsumesOnce() {
    var restoration = ProviderUsageDockFocusRestoration()
    restoration.scheduleReturn(to: "anthropic")

    #expect(restoration.consumeOnCompactMount() == "anthropic")
    #expect(restoration.consumeOnCompactMount() == nil)
}
