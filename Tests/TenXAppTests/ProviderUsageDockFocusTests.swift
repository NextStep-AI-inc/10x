import OmpKit
import Testing
@testable import TenXApp

@Suite struct ProviderUsageDockFocusTests {
@MainActor
@Test func providerUsageDockFocusReturnWaitsForCompactMountAndRestoresTheOpeningAccountOnce() async {
    var routedAccounts: [String] = []
    let interaction = ProviderUsageDockInteraction { accountRef, _ in
        routedAccounts.append(accountRef)
    }
    var focusedAccountIDs: [String] = []

    interaction.inspect(providerID: "anthropic", accountID: "anthropic:work")
    interaction.dismiss()
    await interaction.restoreFocusAfterCompactMount { accountID in
        focusedAccountIDs.append(accountID)
    }
    await interaction.restoreFocusAfterCompactMount { accountID in
        focusedAccountIDs.append(accountID)
    }

    #expect(focusedAccountIDs == ["anthropic:work"])
    #expect(routedAccounts.isEmpty)
}

@MainActor
@Test func inspectingAnAccountNeverRoutesUntilSwitchConfirmation() {
    var routedAccounts: [String] = []
    var routedScope: ProviderAccountScope?
    let interaction = ProviderUsageDockInteraction { accountRef, scope in
        routedAccounts.append(accountRef)
        routedScope = scope
    }

    interaction.inspect(providerID: "anthropic", accountID: "anthropic:work")
    #expect(routedAccounts.isEmpty)

    interaction.beginConfirmation(satisfaction: .none)
    #expect(routedAccounts.isEmpty)

    interaction.confirm(accountRef: "acct_work", satisfaction: .none)
    #expect(routedAccounts == ["acct_work"])
    if case .thisSession = routedScope {
        // Expected default scope.
    } else {
        Issue.record("Expected this-session routing after confirmation")
    }
}

@MainActor
@Test func cancellingSwitchConfirmationDoesNotRoute() {
    var routedAccounts: [String] = []
    let interaction = ProviderUsageDockInteraction { accountRef, _ in
        routedAccounts.append(accountRef)
    }

    interaction.inspect(providerID: "anthropic", accountID: "anthropic:work")
    interaction.beginConfirmation(satisfaction: .none)
    interaction.cancelConfirmation()

    #expect(interaction.inspectedAccountID == "anthropic:work")
    #expect(!interaction.isShowingConfirmation)
    #expect(routedAccounts.isEmpty)
}

@MainActor
@Test func openSessionIdentityChangeCollapsesInspectionAndInvalidatesConfirmation() {
    var routedAccounts: [String] = []
    let interaction = ProviderUsageDockInteraction { accountRef, _ in
        routedAccounts.append(accountRef)
    }

    interaction.inspect(providerID: "anthropic", accountID: "anthropic:work")
    interaction.beginConfirmation(satisfaction: .none)
    interaction.openSessionDidChange()

    #expect(interaction.inspectedProviderID == nil)
    #expect(interaction.inspectedAccountID == nil)
    #expect(!interaction.isShowingConfirmation)
    #expect(routedAccounts.isEmpty)
}

@MainActor
@Test func confirmationSelectsAndDisablesOnlySatisfiedScopes() {
    let satisfaction = ProviderAccountScopeSatisfaction(
        isThisSessionSatisfied: true,
        areAllCurrentSessionsSatisfied: false,
        isAllNewSessionsSatisfied: true)
    let interaction = ProviderUsageDockInteraction { _, _ in }

    interaction.inspect(providerID: "anthropic", accountID: "anthropic:work")
    interaction.beginConfirmation(satisfaction: satisfaction)

    #expect(interaction.selectedScope == .allCurrentSessions)
    #expect(satisfaction.isSatisfied(.thisSession))
    #expect(!satisfaction.isSatisfied(.allCurrentSessions))
    #expect(satisfaction.isSatisfied(.allNewSessions))
    #expect(!satisfaction.areAllScopesSatisfied)
}

@MainActor
@Test func confirmationActionDisablesOnlyWhenEveryScopeIsSatisfied() {
    #expect(!ProviderAccountScopeSatisfaction.none.areAllScopesSatisfied)
    #expect(ProviderAccountScopeSatisfaction.all.areAllScopesSatisfied)
}

@MainActor
@Test func unavailableAndPendingRemovalAccountsCannotBeSelected() {
    let unavailable = dockAccount(
        id: "anthropic:unavailable",
        accountRef: "acct_unavailable",
        availability: .unavailable)
    let available = dockAccount(
        id: "anthropic:available",
        accountRef: "acct_available",
        availability: .available)

    #expect(!ProviderUsageDockRoutingEligibility.canSelect(
        unavailable,
        providerID: "anthropic",
        pendingRemovalAccounts: []))
    #expect(!ProviderUsageDockRoutingEligibility.canSelect(
        available,
        providerID: "anthropic",
        pendingRemovalAccounts: [ProviderAccountKey(
            providerID: "anthropic",
            accountRef: "acct_available")]))
    #expect(ProviderUsageDockRoutingEligibility.canSelect(
        available,
        providerID: "anthropic",
        pendingRemovalAccounts: []))
}

@MainActor
@Test func expandedInspectionRaisesTheInspectedAccountWithoutChangingRoutingState() {
    let personal = dockAccount(
        id: "anthropic:personal",
        accountRef: "acct_personal",
        availability: .available)
    let work = dockAccount(
        id: "anthropic:work",
        accountRef: "acct_work",
        availability: .available)
    let provider = ProviderUsageProvider(
        id: "anthropic",
        name: "Anthropic",
        accounts: [personal, work],
        capability: .accountRouting,
        foregroundAccountRef: "acct_personal")

    let expanded = ProviderUsageDockPresentation.expandedProvider(
        provider,
        inspectedAccount: work)

    #expect(expanded.foregroundAccountRef == "acct_work")
    #expect(expanded.accounts == provider.accounts)
}
}

private func dockAccount(
    id: String,
    accountRef: String,
    availability: ProviderAccountAvailability
) -> ProviderUsageAccount {
    ProviderUsageAccount(
        id: id,
        label: "work@example.com",
        identity: .empty,
        limits: [],
        amounts: [],
        notes: [],
        isUsageAvailable: true,
        accountRef: accountRef,
        availability: availability)
}
