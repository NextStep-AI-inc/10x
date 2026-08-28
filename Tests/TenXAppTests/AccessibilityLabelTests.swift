import Foundation
import Testing
@testable import TenXApp

@Suite struct AccessibilityLabelTests {
@Test func railSessionLabelsIncludeHierarchyAndState() {
    #expect(RailAccessibility.sessionLabel(
        title: "Bauhaus macOS interface",
        project: "10x",
        state: "Running"
    ) == "Bauhaus macOS interface, 10x, Running")
}

@Test func approvalLabelsIncludeTheActionScope() {
    #expect(ApprovalAccessibility.actionLabel(
        name: "Always allow",
        scope: "This project"
    ) == "Always allow, This project")
}

@Test func railOverflowAccessibilityNamesActionsAndCounts() {
    #expect(RailAccessibility.disclosureLabel(hiddenCount: 2, isExpanded: false)
        == "Show 2 more sessions")
    #expect(RailAccessibility.disclosureLabel(hiddenCount: 2, isExpanded: true)
        == "Show recent 5 sessions")
    #expect(RailAccessibility.hiddenSessionsLabel(2) == "2 more sessions")
    #expect(RailAccessibility.scrollLabel(.up) == "Show earlier rail items")
    #expect(RailAccessibility.scrollLabel(.down) == "Show later rail items")
}

@Test func providerUsageLabelNamesRemainingCapacityAndReset() {
    #expect(ProviderUsageAccessibility.limitLabel(
        provider: "Cursor",
        account: "tanner@example.com",
        allowance: "Cursor Models",
        percentage: 50,
        reset: "5 days"
    ) == "Cursor, tanner@example.com, Cursor Models, 50 percent remaining, resets in 5 days")
}

@Test func providerUsageLabelNamesUnavailableResetWhenWindowIsMissing() {
    #expect(ProviderUsageAccessibility.limitLabel(
        provider: "Cursor",
        account: nil,
        allowance: "Cursor Models",
        percentage: 50,
        reset: ""
    ) == "Cursor, Cursor Models, 50 percent remaining, reset unavailable")
}

@Test func providerUsageLabelNamesUnavailableResetWhenWindowIsWhitespace() {
    #expect(ProviderUsageAccessibility.limitLabel(
        provider: "Cursor",
        account: nil,
        allowance: "Cursor Models",
        percentage: 50,
        reset: "  \n\t "
    ) == "Cursor, Cursor Models, 50 percent remaining, reset unavailable")
}

@Test func providerUsageDetailLabelIncludesProviderAndAccountLikeTheRail() {
    #expect(ProviderUsageDetailAccessibility.limitLabel(
        provider: "Cursor",
        account: "tanner@example.com",
        allowance: "Cursor Models",
        percentage: 50,
        reset: "Aug 30, 9:00 AM"
    ) == "Cursor, tanner@example.com, Cursor Models, 50 percent remaining, resets in Aug 30, 9:00 AM")
}

@Test func providerUsageWheelValueNamesProviderActivityAndOrderedLimits() {
    let provider = ProviderUsageProvider(
        id: "cursor",
        name: "Cursor",
        accounts: [ProviderUsageAccount(
            id: "cursor:primary",
            label: "Primary",
            identity: ProviderUsageAccountIdentity(
                email: nil,
                accountID: nil,
                projectID: nil,
                enterpriseURL: nil,
                orgID: nil,
                orgName: nil),
            limits: [
                ProviderUsageLimit(
                    id: "five-hour",
                    label: "5 hour",
                    percentage: 20,
                    detailReset: "in 35 minutes",
                    railReset: "35m",
                    windowDurationRank: 1),
                ProviderUsageLimit(
                    id: "weekly",
                    label: "Weekly",
                    percentage: 80,
                    detailReset: "in 5 days",
                    railReset: "5d",
                    windowDurationRank: 2),
            ],
            amounts: [],
            notes: [],
            isUsageAvailable: true)],
    )

    #expect(ProviderUsageAccessibility.wheelValue(provider: provider, activeCount: 0)
        == "Cursor, No active sessions, 5 hour, 20 percent remaining, resets in 35m, Weekly, 80 percent remaining, resets in 5d")
    #expect(ProviderUsageAccessibility.wheelValue(provider: provider, activeCount: 1)
        .contains("1 active session"))
    #expect(ProviderUsageAccessibility.wheelValue(provider: provider, activeCount: 2)
        .contains("2 active sessions"))
    #expect(ProviderUsageAccessibility.wheelValue(provider: provider, activeCount: 2)
        .contains("5 hour, 20 percent remaining"))
}

@Test func providerAccountWheelAccessibilityNamesSafeIdentityActivityAndLimits() {
    let account = ProviderUsageAccount(
        id: "anthropic:work",
        label: "work@example.com",
        identity: .empty,
        limits: [ProviderUsageLimit(
            id: "five-hour",
            label: "5 hour",
            percentage: 82,
            resetWindow: "in 2 hours")],
        amounts: [],
        notes: [],
        isUsageAvailable: true,
        accountRef: "acct_work")

    #expect(ProviderUsageAccessibility.accountWheelLabel(
        provider: "Anthropic",
        account: account) == "Anthropic, work@example.com")
    #expect(ProviderUsageAccessibility.accountWheelValue(
        account: account,
        activeCount: 2
    ) == "work@example.com, 2 active sessions, 5 hour, 82 percent remaining, resets in 2 hours")
}

@Test func providerAccountSwitchConfirmationUsesExactCopyAndStableRadioOrder() {
    let presentation = ProviderAccountSwitchConfirmationPresentation(accountLabel: "work@example.com")

    #expect(presentation.title == "Use work@example.com?")
    #expect(presentation.message == "Choose where this account should be used.")
    #expect(presentation.options.map(\.title) == [
        "This session",
        "All current sessions",
        "All new sessions",
    ])
    #expect(presentation.options.map(\.message) == [
        "Switch the open session. If it is generating, switch after the current turn.",
        "Switch every 10x-managed session using this provider. Generating sessions finish their current turn first.",
        "Set this as the provider's primary account. Existing sessions stay unchanged.",
    ])
    #expect(presentation.cancelActionLabel == "Cancel")
    #expect(presentation.confirmActionLabel == "Switch account")
    #expect(presentation.usesRadioGroupSemantics)
}

@MainActor
@Test func updateRowsAnnounceTheirTitleAndStatus() {
    let state = UpdateState()
    state.beginDownload()

    #expect(state.rows.map(\.accessibilityLabel) == [
        "Downloading update, Loading",
        "Verifying download, Queued",
        "Installing update, Queued",
        "Relaunching 10x, Queued",
    ])
}

@MainActor
@Test func updateModeRelabelsTheWindowForVoiceOver() {
    let state = UpdateState()
    state.showAvailable(newVersion: "0.2.0", currentVersion: "0.1.0")

    let presentation = SplashPresentation.update(
        state: state, onInstall: {}, onDismiss: {}, onRetry: {})

    #expect(presentation.accessibilityLabel == "Update available")
}

@MainActor
@Test func theInstallActionIsFirstInFocusOrder() {
    let state = UpdateState()
    state.showAvailable(newVersion: "0.2.0", currentVersion: "0.1.0")

    let presentation = SplashPresentation.update(
        state: state, onInstall: {}, onDismiss: {}, onRetry: {})

    #expect(presentation.actions.first?.kind == .primary)
    #expect(presentation.actions.first?.title == "Install and relaunch")
}

@MainActor
private func startupPresentation(_ state: StartupState) -> SplashPresentation {
    SplashPresentation.startup(state: state, onRetry: {}, onContinue: {})
}

@MainActor
private func updatePresentation(_ state: UpdateState) -> SplashPresentation {
    SplashPresentation.update(state: state, onInstall: {}, onDismiss: {}, onRetry: {})
}

/// `SplashView` focuses the primary action and speaks a summary when this changes.
/// It previously did so only on appearance and on the footer turning red, so an update
/// offered during startup, which is neither, never took focus at all.
@MainActor
@Test func anUpdateOfferedDuringStartupIsANewScreen() {
    let startup = StartupState()
    startup.beginAttempt(id: UUID())
    let offered = UpdateState()
    offered.beginCheck(isUserInitiated: false)
    offered.showAvailable(newVersion: "0.2.0", currentVersion: "0.1.0")

    #expect(
        startupPresentation(startup).screenSignature
            != updatePresentation(offered).screenSignature)
}

/// Progress within one run is not a new screen. Re-announcing and re-grabbing focus on
/// every download tick would talk over the user.
@MainActor
@Test func downloadProgressIsNotANewScreen() {
    let state = UpdateState()
    state.beginDownload()
    state.setExpectedBytes(1_000)
    let atStart = updatePresentation(state).screenSignature
    state.addReceivedBytes(400)

    #expect(updatePresentation(state).screenSignature == atStart)
}

/// A failure inside a run is a new screen even though the umbrella heading does not
/// change, because the actions and the tone do.
@MainActor
@Test func aFailureInsideARunIsANewScreen() {
    let state = UpdateState()
    state.beginDownload()
    let downloading = updatePresentation(state).screenSignature
    state.fail(.download)

    #expect(updatePresentation(state).screenSignature != downloading)
}

/// The row announcer diffs by id against the previous composition. Startup rows and
/// update rows share no ids, so a diff across that boundary reports every update step as
/// newly `Queued`. `SplashView` suppresses the diff when the id set changes; this pins
/// that the two ledgers really are disjoint, which is what makes the check work.
@MainActor
@Test func theStartupAndUpdateLedgersShareNoRowIDs() {
    let startup = StartupState()
    let update = UpdateState()
    update.beginDownload()

    let startupIDs = Set(startup.rows.map(\.id))
    let updateIDs = Set(update.rows.map(\.id))

    #expect(!updateIDs.isEmpty)
    #expect(startupIDs.isDisjoint(with: updateIDs))
}

/// The two presentations share `StartupLedgerView`, whose container label was hardcoded
/// to "Startup preparation" and so described the update steps as startup steps.
@MainActor
@Test func eachLedgerNamesWhatItIsAListOf() {
    let startup = StartupState()
    let update = UpdateState()
    update.beginDownload()

    #expect(startupPresentation(startup).ledgerAccessibilityLabel == "Startup preparation")
    #expect(updatePresentation(update).ledgerAccessibilityLabel == "Update steps")
}
}
