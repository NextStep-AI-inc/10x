import Testing
@testable import TenXApp

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
