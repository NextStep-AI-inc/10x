import Testing
@testable import TenXApp

@MainActor
@Test func providerUsageDockFocusReturnWaitsForCompactMountAndAssignsOnce() async {
    let restoration = ProviderUsageDockFocusRestorationCoordinator()
    var focusedProviderIDs: [String] = []

    restoration.scheduleReturn(to: "anthropic")
    await restoration.restoreAfterCompactMount { providerID in
        focusedProviderIDs.append(providerID)
    }
    await restoration.restoreAfterCompactMount { providerID in
        focusedProviderIDs.append(providerID)
    }

    #expect(focusedProviderIDs == ["anthropic"])
}
