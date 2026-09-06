import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Test func expandedModeOpensEveryToolIncludingQuietCompletions() {
    let mode = ToolDetailMode.expanded
    #expect(mode.isExpandedByDefault(traits(name: "read", phase: .complete)))
    #expect(mode.isExpandedByDefault(traits(name: "glob", phase: .complete)))
    #expect(mode.isExpandedByDefault(traits(name: "bash", phase: .running)))
    #expect(mode.opensGroupsByDefault)
}

@Test func standardModeKeepsGroupsOpenAndToolsClosed() {
    let mode = ToolDetailMode.standard
    #expect(!mode.isExpandedByDefault(traits(name: "read", phase: .complete)))
    #expect(!mode.isExpandedByDefault(traits(name: "edit", phase: .complete)))
    #expect(!mode.isExpandedByDefault(traits(name: "bash", phase: .running)))
    #expect(!mode.isExpandedByDefault(traits(name: "bash", phase: .failed)))
    #expect(mode.opensGroupsByDefault)
}

@Test func slimModeKeepsGroupsAndToolsClosed() {
    let mode = ToolDetailMode.slim
    #expect(!mode.isExpandedByDefault(traits(name: "read", phase: .complete)))
    #expect(!mode.isExpandedByDefault(traits(name: "edit", phase: .complete)))
    #expect(!mode.isExpandedByDefault(traits(name: "bash", phase: .running)))
    #expect(!mode.opensGroupsByDefault)
}

@Test func disclosureStateResolvesRowsThroughItsMode() {
    let read = detailTool(id: "read", name: "read", phase: .complete)

    #expect(!ToolDisclosureState(mode: .standard).isExpanded(for: read))
    #expect(ToolDisclosureState(mode: .expanded).isExpanded(for: read))
    #expect(!ToolDisclosureState(mode: .slim).isExpanded(for: read))
}

@Test func disclosureStateResolvesGroupsThroughItsMode() {
    #expect(ToolDisclosureState(mode: .expanded).isGroupExpanded(id: "tool-group-one"))
    #expect(ToolDisclosureState(mode: .standard).isGroupExpanded(id: "tool-group-one"))
    #expect(!ToolDisclosureState(mode: .slim).isGroupExpanded(id: "tool-group-one"))
}

@Test func perCardChoiceOverridesTheModeForThatCardOnly() {
    let state = ToolDisclosureState(mode: .slim)
    let opened = detailTool(id: "opened", name: "read", phase: .complete)
    let neighbor = detailTool(id: "neighbor", name: "read", phase: .complete)

    state.setExpanded(true, for: opened)

    #expect(state.isExpanded(for: opened))
    #expect(!state.isExpanded(for: neighbor))
}

@Test func changingModeDiscardsEarlierPerCardAndGroupChoices() {
    let state = ToolDisclosureState(mode: .standard)
    let closedByHand = detailTool(id: "closed", name: "bash", phase: .running)
    state.setExpanded(false, for: closedByHand)
    state.setGroupExpanded(false, id: "tool-group-one")
    #expect(!state.isExpanded(for: closedByHand))
    #expect(!state.isGroupExpanded(id: "tool-group-one"))

    state.setMode(.expanded)
    #expect(state.isExpanded(for: closedByHand))
    #expect(state.isGroupExpanded(id: "tool-group-one"))

    state.setGroupExpanded(true, id: "tool-group-one")
    state.setMode(.slim)
    #expect(!state.isGroupExpanded(id: "tool-group-one"))
}

@Test func reselectingTheCurrentModeKeepsPerCardChoices() {
    let state = ToolDisclosureState(mode: .standard)
    let openedByHand = detailTool(id: "opened", name: "bash", phase: .complete)
    state.setExpanded(true, for: openedByHand)

    state.setMode(.standard)
    #expect(state.isExpanded(for: openedByHand))
}

@Test func subagentRowsFollowTheSameModeAsToolRows() {
    let finished = detailSubagent(id: "finished", status: .completed)
    let running = detailSubagent(id: "running", status: .running)
    let failed = detailSubagent(id: "failed", status: .failed)

    let standard = ToolDisclosureState(mode: .standard)
    #expect(!standard.isExpanded(for: finished))
    #expect(!standard.isExpanded(for: running))
    #expect(!standard.isExpanded(for: failed))

    #expect(ToolDisclosureState(mode: .expanded).isExpanded(for: finished))
    #expect(!ToolDisclosureState(mode: .slim).isExpanded(for: running))
    #expect(!ToolDisclosureState(mode: .slim).isExpanded(for: failed))
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
@Test func preferenceStoreFallsBackToStandardWithoutAUsableStoredValue() throws {
    try withIsolatedDefaults { defaults in
        #expect(ToolDetailPreferenceStore(defaults: defaults).mode == .standard)

        defaults.set("verbose", forKey: ToolDetailPreferenceStore.defaultsKey)
        #expect(ToolDetailPreferenceStore(defaults: defaults).mode == .standard)

        defaults.set(3, forKey: ToolDetailPreferenceStore.defaultsKey)
        #expect(ToolDetailPreferenceStore(defaults: defaults).mode == .standard)
    }
}

@MainActor
@Test func preferenceStoreMigratesRetiredRawValues() throws {
    try withIsolatedDefaults { defaults in
        defaults.set("auto", forKey: ToolDetailPreferenceStore.defaultsKey)
        #expect(ToolDetailPreferenceStore(defaults: defaults).mode == .standard)

        defaults.set("compact", forKey: ToolDetailPreferenceStore.defaultsKey)
        #expect(ToolDetailPreferenceStore(defaults: defaults).mode == .slim)
    }
}

@Test func modeChipsReadExpandedThenStandardThenSlim() {
    #expect(ToolDetailMode.allCases == [.expanded, .standard, .slim])
    #expect(ToolDetailMode.allCases.map(\.title) == ["Expanded", "Standard", "Slim"])
    #expect(ToolDetailMode.expanded.accessibilityTitle == "Expanded")
}

@Test func slimGroupLineShowsTheToolCallAndItsInfo() {
    let read = readTool(id: "one", path: "/tmp/README.md")
    let group = try! #require(TranscriptToolGroup([read]))
    let presentation = ToolCallGroupHeaderPresentation(group: group, mode: .slim)

    #expect(presentation.usesInlineToolInfo)
    #expect(presentation.title == read.content.verb)
    #expect(presentation.info == read.content.primary)
    #expect(presentation.info != nil)
}

@Test func slimGroupLineJoinsMultipleToolCalls() {
    let read = readTool(id: "one", path: "/tmp/README.md")
    let write = readTool(id: "two", name: "write", path: "/tmp/notes.md")
    let group = try! #require(TranscriptToolGroup([read, write]))
    let presentation = ToolCallGroupHeaderPresentation(group: group, mode: .slim)

    #expect(presentation.usesInlineToolInfo)
    #expect(presentation.title.contains(read.content.verb))
    #expect(presentation.title.contains(write.content.verb))
    #expect(presentation.info == nil)
}

@Test func standardGroupLineKeepsTheGenericToolCallTitle() {
    let read = readTool(id: "one", path: "/tmp/README.md")
    let group = try! #require(TranscriptToolGroup([read]))
    let presentation = ToolCallGroupHeaderPresentation(group: group, mode: .standard)

    #expect(!presentation.usesInlineToolInfo)
    #expect(presentation.title == "Tool call")
    #expect(presentation.info == nil)
}

@Test func expandedGroupLineKeepsTheGenericToolCallTitle() {
    let read = readTool(id: "one", path: "/tmp/README.md")
    let group = try! #require(TranscriptToolGroup([read]))
    let presentation = ToolCallGroupHeaderPresentation(group: group, mode: .expanded)

    #expect(!presentation.usesInlineToolInfo)
    #expect(presentation.title == "Tool call")
    #expect(presentation.info == nil)
}

@Test func slimGroupLineIncludesEveryToolWhenTheGroupHasSeveral() {
    let read = readTool(id: "one", path: "/tmp/README.md")
    let write = readTool(id: "two", name: "write", path: "/tmp/notes.md")
    let glob = readTool(id: "three", name: "glob", path: "App/**/*.swift")
    let group = try! #require(TranscriptToolGroup([read, write, glob]))
    let presentation = ToolCallGroupHeaderPresentation(group: group, mode: .slim)

    #expect(presentation.usesInlineToolInfo)
    #expect(presentation.title.contains(read.content.verb))
    #expect(presentation.title.contains(write.content.verb))
    #expect(presentation.title.contains(glob.content.verb))
    #expect(presentation.info == nil)
}

@Test func slimVisibleRowsHideGroupedToolsUntilTheGroupIsOpened() {
    let read = readTool(id: "one", path: "/tmp/README.md")
    let write = readTool(id: "two", name: "write", path: "/tmp/notes.md")
    let rows = TranscriptPresentationRow.rows(from: [.tool(read), .tool(write)])
    let state = ToolDisclosureState(mode: .slim)

    let visible = TranscriptPresentationRow.visibleRows(
        from: rows,
        isGroupExpanded: state.isGroupExpanded)

    #expect(visible.map(\.id) == ["tool-group-one"])
    state.setGroupExpanded(true, id: "tool-group-one")
    let opened = TranscriptPresentationRow.visibleRows(
        from: rows,
        isGroupExpanded: state.isGroupExpanded)
    #expect(opened.map(\.id) == ["tool-group-one", "tool:one", "tool:two"])
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

private func readTool(id: String, name: String = "read", path: String) -> ToolPresentation {
    ToolPresentation(
        id: id,
        name: name,
        arguments: .object(["absolutePath": .string(path)]),
        result: nil,
        phase: .complete,
        startDate: Date(timeIntervalSince1970: 1),
        endDate: Date(timeIntervalSince1970: 2))
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
