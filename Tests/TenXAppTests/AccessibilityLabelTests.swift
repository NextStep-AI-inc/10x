import Testing
@testable import TenXApp

@Test func railSessionLabelsIncludeHierarchyAndState() {
    #expect(RailAccessibility.sessionLabel(
        title: "Bauhaus macOS interface",
        project: "10x",
        state: "Running"
    ) == "Bauhaus macOS interface, 10x, Running")
}

@Test func railSessionLabelsAppendComputerUseWhenBadged() {
    #expect(RailAccessibility.sessionLabel(
        title: "Bauhaus macOS interface",
        project: "10x",
        state: "Running",
        hasComputerUse: true
    ) == "Bauhaus macOS interface, 10x, Running, Computer use active")
}

@Test func approvalLabelsIncludeTheActionScope() {
    #expect(ApprovalAccessibility.actionLabel(
        name: "Always allow",
        scope: "This project"
    ) == "Always allow, This project")
}
