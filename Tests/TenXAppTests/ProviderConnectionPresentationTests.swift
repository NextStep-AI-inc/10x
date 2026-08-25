import Testing
@testable import TenXApp

@Test func connectionRowsPrioritizeUnavailableAndDisableCompetingLogins() {
    let unavailable = ProviderLoginProvider(
        id: "cursor", name: "Cursor", isAvailable: false, isAuthenticated: false)
    let unavailablePresentation = ProviderConnectionRowPresentation.make(
        provider: unavailable,
        hasCredentialIssue: true,
        activeLoginProviderID: "anthropic",
        loginMessage: "Couldn’t connect to Cursor.")

    #expect(unavailablePresentation.status == "Unavailable")
    #expect(unavailablePresentation.action == .unavailable)
    #expect(unavailablePresentation.isActionDisabled == false)

    let reconnect = ProviderConnectionRowPresentation.make(
        provider: ProviderLoginProvider(
            id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: false),
        hasCredentialIssue: true,
        activeLoginProviderID: "anthropic",
        loginMessage: nil)

    #expect(reconnect.action == .reconnect)
    #expect(reconnect.isActionDisabled)
}

@Test func connectionRowsOfferRetryAndAccurateAccessibilityAfterProviderFailure() {
    let presentation = ProviderConnectionRowPresentation.make(
        provider: ProviderLoginProvider(
            id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: false),
        hasCredentialIssue: true,
        activeLoginProviderID: nil,
        loginMessage: "Couldn’t connect to Cursor.")

    #expect(presentation.action == .retry)
    #expect(presentation.accessibilityLabel == "Retry Cursor connection")
}
