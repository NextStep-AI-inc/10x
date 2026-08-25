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
