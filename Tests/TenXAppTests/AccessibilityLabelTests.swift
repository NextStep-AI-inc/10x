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
