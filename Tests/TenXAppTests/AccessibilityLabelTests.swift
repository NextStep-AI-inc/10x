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
    #expect(presentation.actions.first?.title == "Install and Relaunch")
}
}
