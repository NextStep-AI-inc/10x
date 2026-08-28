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
@Test func providerOnlyInspectionRestoresTheProviderFocusID() async {
    let interaction = ProviderUsageDockInteraction(
        initiallyInspectedProviderID: "cursor",
        onUseAccount: { _, _ in })
    var focusedIDs: [String] = []

    interaction.dismiss()
    await interaction.restoreFocusAfterCompactMount { focusedIDs.append($0) }

    #expect(interaction.inspectedProviderID == nil)
    #expect(interaction.inspectedAccountID == nil)
    #expect(focusedIDs == ["cursor"])
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
@Test func newSessionConfirmationSkipsScopesWithoutManagedSessions() {
    var routedScope: ProviderAccountScope?
    let interaction = ProviderUsageDockInteraction { _, scope in
        routedScope = scope
    }
    let availability = ProviderAccountScopeAvailability.newSessionsOnly

    interaction.inspect(providerID: "anthropic", accountID: "anthropic:work")
    interaction.beginConfirmation(
        satisfaction: .none,
        availability: availability)

    #expect(interaction.selectedScope == .allNewSessions)

    interaction.selectScope(
        .thisSession,
        satisfaction: .none,
        availability: availability)
    #expect(interaction.selectedScope == .allNewSessions)

    interaction.confirm(
        accountRef: "acct_work",
        satisfaction: .none,
        availability: availability)
    if case .allNewSessions = routedScope {
        // The only available scope is routed.
    } else {
        Issue.record("Expected all-new-sessions routing")
    }
}

@MainActor
@Test func staleSatisfiedScopeRequiresExplicitUnsatisfiedSelection() {
    var routedScope: ProviderAccountScope?
    let interaction = ProviderUsageDockInteraction { _, scope in
        routedScope = scope
    }
    interaction.inspect(providerID: "anthropic", accountID: "anthropic:work")
    interaction.beginConfirmation(satisfaction: .none)
    let updatedSatisfaction = ProviderAccountScopeSatisfaction(
        isThisSessionSatisfied: true,
        areAllCurrentSessionsSatisfied: false,
        isAllNewSessionsSatisfied: false)

    interaction.confirm(accountRef: "acct_work", satisfaction: updatedSatisfaction)

    #expect(routedScope == nil)
    #expect(interaction.isShowingConfirmation)
    #expect(interaction.selectedScope == .thisSession)

    interaction.selectScope(.allNewSessions, satisfaction: updatedSatisfaction)
    interaction.confirm(accountRef: "acct_work", satisfaction: updatedSatisfaction)
    if case .allNewSessions = routedScope {
        // The explicitly selected unsatisfied scope is routed.
    } else {
        Issue.record("Expected all-new-sessions routing after explicit reselection")
    }
}

@MainActor
@Test func confirmationActionDisablesOnlyWhenEveryScopeIsSatisfied() {
    #expect(!ProviderAccountScopeSatisfaction.none.areAllScopesSatisfied)
    #expect(ProviderAccountScopeSatisfaction.all.areAllScopesSatisfied)
}

@MainActor
@Test func unavailableAndPendingRemovalAccountsRemainInspectableButCannotSwitch() {
    let interaction = ProviderUsageDockInteraction { _, _ in }
    let unavailable = dockAccount(
        id: "anthropic:unavailable",
        accountRef: "acct_unavailable",
        availability: .unavailable)
    let available = dockAccount(
        id: "anthropic:available",
        accountRef: "acct_available",
        availability: .available)

    interaction.inspect(providerID: "anthropic", accountID: unavailable.id)
    #expect(interaction.inspectedAccountID == unavailable.id)
    #expect(!ProviderUsageDockRoutingEligibility.canSwitch(
        unavailable,
        providerID: "anthropic",
        pendingRemovalAccounts: []))

    interaction.inspect(providerID: "anthropic", accountID: available.id)
    #expect(interaction.inspectedAccountID == available.id)
    #expect(!ProviderUsageDockRoutingEligibility.canSwitch(
        available,
        providerID: "anthropic",
        pendingRemovalAccounts: [ProviderAccountKey(
            providerID: "anthropic",
            accountRef: "acct_available")]))
    #expect(ProviderUsageDockRoutingEligibility.canSwitch(
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

@MainActor
@Test func dockExpansionUsesMatchedGeometryUnlessReduceMotionIsEnabled() {
    #expect(ProviderUsageDockExpansionMotion.mode(reduceMotion: false) == .matchedGeometry)
    #expect(ProviderUsageDockExpansionMotion.mode(reduceMotion: true) == .identity)
}

@MainActor
@Test func switchConfirmationAssignsInitialFocusToCancelDeterministically() async {
    var targets: [ProviderAccountSwitchConfirmationFocusTarget] = []

    await ProviderAccountSwitchConfirmationFocus.assignInitialFocus {
        targets.append($0)
    }

    #expect(targets == [.cancel])
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
