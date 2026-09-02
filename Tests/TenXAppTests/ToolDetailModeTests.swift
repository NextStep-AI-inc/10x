import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Test func autoModeReproducesTheExistingDisclosureDefaults() {
    let mode = ToolDetailMode.auto
    #expect(mode.isExpandedByDefault(traits(name: "bash", phase: .running)))
    #expect(mode.isExpandedByDefault(traits(name: "bash", phase: .failed)))
    #expect(mode.isExpandedByDefault(traits(name: "edit", phase: .complete)))
    #expect(mode.isExpandedByDefault(traits(name: "resolve", phase: .complete)))
    #expect(!mode.isExpandedByDefault(traits(name: "read", phase: .complete)))
}

@Test func expandedModeOpensEveryRowIncludingQuietCompletions() {
    let mode = ToolDetailMode.expanded
    #expect(mode.isExpandedByDefault(traits(name: "read", phase: .complete)))
    #expect(mode.isExpandedByDefault(traits(name: "glob", phase: .complete)))
    #expect(mode.isExpandedByDefault(traits(name: "bash", phase: .running)))
}

@Test func compactModeClosesEveryRowIncludingFailuresAndEdits() {
    let mode = ToolDetailMode.compact
    #expect(!mode.isExpandedByDefault(traits(name: "read", phase: .complete)))
    #expect(!mode.isExpandedByDefault(traits(name: "edit", phase: .complete)))
    #expect(!mode.isExpandedByDefault(traits(name: "bash", phase: .running)))
    #expect(!mode.isExpandedByDefault(traits(name: "bash", phase: .failed)))
}

@Test func disclosureStateResolvesRowsThroughItsMode() {
    let read = detailTool(id: "read", name: "read", phase: .complete)

    #expect(!ToolDisclosureState(mode: .auto).isExpanded(for: read))
    #expect(ToolDisclosureState(mode: .expanded).isExpanded(for: read))
    #expect(!ToolDisclosureState(mode: .compact).isExpanded(for: read))
}

@Test func perCardChoiceOverridesTheModeForThatCardOnly() {
    let state = ToolDisclosureState(mode: .compact)
    let opened = detailTool(id: "opened", name: "read", phase: .complete)
    let neighbor = detailTool(id: "neighbor", name: "read", phase: .complete)

    state.setExpanded(true, for: opened)

    #expect(state.isExpanded(for: opened))
    #expect(!state.isExpanded(for: neighbor))
}

@Test func changingModeDiscardsEarlierPerCardChoices() {
    let state = ToolDisclosureState(mode: .auto)
    let closedByHand = detailTool(id: "closed", name: "bash", phase: .running)
    state.setExpanded(false, for: closedByHand)
    #expect(!state.isExpanded(for: closedByHand))

    state.setMode(.expanded)
    #expect(state.isExpanded(for: closedByHand))
}

@Test func reselectingTheCurrentModeKeepsPerCardChoices() {
    let state = ToolDisclosureState(mode: .auto)
    let closedByHand = detailTool(id: "closed", name: "bash", phase: .running)
    state.setExpanded(false, for: closedByHand)

    state.setMode(.auto)
    #expect(!state.isExpanded(for: closedByHand))
}

@Test func subagentRowsFollowTheSameModeAsToolRows() {
    let finished = detailSubagent(id: "finished", status: .completed)
    let running = detailSubagent(id: "running", status: .running)
    let failed = detailSubagent(id: "failed", status: .failed)

    let auto = ToolDisclosureState(mode: .auto)
    #expect(!auto.isExpanded(for: finished))
    #expect(auto.isExpanded(for: running))
    #expect(auto.isExpanded(for: failed))

    #expect(ToolDisclosureState(mode: .expanded).isExpanded(for: finished))
    #expect(!ToolDisclosureState(mode: .compact).isExpanded(for: running))
    #expect(!ToolDisclosureState(mode: .compact).isExpanded(for: failed))
}

@MainActor
@Test func preferenceStoreRoundTripsEveryModeThroughDefaults() throws {
    for mode in ToolDetailMode.allCases {
        try withIsolatedDefaults { defaults in
            ToolDetailPreferenceStore(defaults: defaults).select(mode)

            #expect(ToolDetailPreferenceStore(defaults: defaults).mode == mode)
        }
    }
}

@MainActor
@Test func preferenceStoreFallsBackToAutoWithoutAUsableStoredValue() throws {
    try withIsolatedDefaults { defaults in
        #expect(ToolDetailPreferenceStore(defaults: defaults).mode == .auto)

        defaults.set("verbose", forKey: ToolDetailPreferenceStore.defaultsKey)
        #expect(ToolDetailPreferenceStore(defaults: defaults).mode == .auto)

        defaults.set(3, forKey: ToolDetailPreferenceStore.defaultsKey)
        #expect(ToolDetailPreferenceStore(defaults: defaults).mode == .auto)
    }
}

@Test func modeChipsReadInTheOrderTheyEscalateDetail() {
    #expect(ToolDetailMode.allCases == [.auto, .expanded, .compact])
    #expect(ToolDetailMode.allCases.map(\.title) == ["auto", "expanded", "compact"])
    #expect(ToolDetailMode.expanded.accessibilityTitle == "Expanded")
}

/// One fixed suite, cleared around each use. A UUID-named suite per case leaks
/// a preference domain per run, and the suite list is machine-global. Both
/// callers are `@MainActor`, so they cannot share it concurrently.
private func withIsolatedDefaults(_ body: (UserDefaults) throws -> Void) throws {
    let defaults = try #require(UserDefaults(suiteName: "tenx.tests.toolDetail"))
    defaults.removeObject(forKey: ToolDetailPreferenceStore.defaultsKey)
    defer { defaults.removeObject(forKey: ToolDetailPreferenceStore.defaultsKey) }
    try body(defaults)
}

private func traits(name: String, phase: ToolPhase) -> ToolDisclosureTraits {
    detailTool(id: name, name: name, phase: phase).disclosureTraits
}

private func detailTool(id: String, name: String, phase: ToolPhase) -> ToolPresentation {
    ToolPresentation(
        id: id,
        name: name,
        arguments: .object([:]),
        result: nil,
        phase: phase,
        startDate: Date(timeIntervalSince1970: 1),
        endDate: phase == .running ? nil : Date(timeIntervalSince1970: 2))
}

private func detailSubagent(id: String, status: SubagentStatus) -> SubagentPresentation {
    SubagentPresentation(
        id: id,
        index: 0,
        agent: "reviewer",
        task: "Review transcript behavior",
        assignment: nil,
        description: nil,
        status: status,
        sessionFile: nil,
        parentToolCallID: nil,
        actualModel: nil,
        thinkingLevel: nil,
        modelRole: nil,
        isFallback: false,
        currentTool: nil,
        recentTools: [],
        recentOutput: [],
        toolCount: 0,
        requests: nil,
        tokens: nil,
        cost: nil,
        durationMilliseconds: 0,
        result: nil)
}
