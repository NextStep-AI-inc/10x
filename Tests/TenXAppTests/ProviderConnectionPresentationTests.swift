import Testing
@testable import TenXApp

@Test func curatedProvidersUseCompanyNames() {
    let providers = [
        ProviderLoginProvider(
            id: "cursor", name: "Cursor (Claude, GPT, etc.)", isAvailable: true, isAuthenticated: true),
        ProviderLoginProvider(
            id: "openai-codex", name: "ChatGPT Plus/Pro (Codex Subscription)", isAvailable: true, isAuthenticated: false),
        ProviderLoginProvider(
            id: "anthropic", name: "Anthropic (Claude Pro/Max)", isAvailable: true, isAuthenticated: false),
        ProviderLoginProvider(
            id: "google-gemini-cli", name: "Google Cloud Code Assist (Gemini CLI)", isAvailable: true, isAuthenticated: false),
    ]

    let names = providers.map {
        ProviderConnectionRowPresentation.make(
            provider: $0,
            hasCredentialIssue: false,
            activeLoginProviderID: nil,
            loginMessage: nil).companyName
    }

    #expect(names == ["Cursor", "OpenAI", "Anthropic", "Google"])
}

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

@Test func connectionRowsPresentAuthenticatedUnavailableProvidersConsistently() {
    let presentation = ProviderConnectionRowPresentation.make(
        provider: ProviderLoginProvider(
            id: "cursor", name: "Cursor", isAvailable: false, isAuthenticated: true),
        hasCredentialIssue: false,
        activeLoginProviderID: nil,
        loginMessage: nil)

    #expect(presentation.status == "Unavailable")
    #expect(presentation.action == .unavailable)
    #expect(presentation.isActionDisabled == false)
    #expect(presentation.accessibilityLabel == "Cursor unavailable")
}
