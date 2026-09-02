import Foundation
import Observation
import OmpKit
import Testing
@testable import TenXApp

@Test func disclosureDefaultsMatchActivityStateAndKind() {
    let state = ToolDisclosureState()
    #expect(!state.isExpanded(for: tool(id: "read", name: "read", phase: .complete)))
    #expect(state.isExpanded(for: tool(id: "running", name: "bash", phase: .running)))
    #expect(state.isExpanded(for: tool(id: "failed", name: "bash", phase: .failed)))
    #expect(state.isExpanded(for: tool(id: "diff", name: "edit", phase: .complete)))
}

@Test func userDisclosureChoicePersistsAcrossPhaseChanges() {
    let state = ToolDisclosureState()
    let running = tool(id: "same", name: "bash", phase: .running)
    state.setExpanded(false, for: running)

    #expect(!state.isExpanded(for: running))
    #expect(!state.isExpanded(for: tool(id: "same", name: "bash", phase: .complete)))

    state.setExpanded(true, for: tool(id: "same", name: "bash", phase: .complete))
    #expect(state.isExpanded(for: tool(id: "same", name: "bash", phase: .complete)))
}

@Test func transcriptDisclosureCommandsAffectOnlyTheirIntendedRows() {
    let state = ToolDisclosureState()
    let complete = tool(id: "complete", name: "read", phase: .complete)
    let running = tool(id: "running", name: "bash", phase: .running)
    let failed = tool(id: "failed", name: "bash", phase: .failed)

    state.collapseAll(ids: [complete.id, running.id, failed.id])
    #expect(!state.isExpanded(for: running))
    #expect(!state.isExpanded(for: failed))

    state.expand(ids: [running.id, failed.id])
    #expect(!state.isExpanded(for: complete))
    #expect(state.isExpanded(for: running))
    #expect(state.isExpanded(for: failed))
}

@Test func compactToolHeaderNamesObjectOutcomeAndLifecycle() {
    let header = ToolCardHeaderPresentation(
        content: ToolCardContent(
            title: "Read",
            verb: "Read",
            primary: "App.swift",
            outcome: "42 lines",
            reference: nil,
            body: .empty("Completed without output")),
        phase: .complete,
        duration: "0.3s")

    #expect(header.visibleText == "Read App.swift · 42 lines")
    #expect(header.accessibilityLabel == "Read App.swift, 42 lines, Complete, 0.3 seconds")
}

@Test func compactToolHeaderDoesNotRepeatLifecycleAsOutcome() {
    let header = ToolCardHeaderPresentation(
        content: ToolCardContent(
            title: "Run",
            verb: "Run",
            primary: "xcodebuild test",
            outcome: "Running",
            reference: nil,
            body: .empty("")),
        phase: .running,
        duration: "4.2s")

    #expect(header.visibleText == "Run xcodebuild test")
    #expect(header.accessibilityLabel == "Run xcodebuild test, Running, 4.2 seconds")
}

@Test func attentionToolsDefaultExpandedAfterCompletion() {
    #expect(ToolDisclosureState.defaultExpanded(
        for: tool(id: "edit", name: "edit", phase: .complete)))
    #expect(ToolDisclosureState.defaultExpanded(
        for: tool(id: "proposal", name: "resolve", phase: .complete)))
    #expect(!ToolDisclosureState.defaultExpanded(
        for: tool(id: "read", name: "read", phase: .complete)))
}

@Test func sharedToolDisclosureMeetsTheMinimumHitTarget() {
    #expect(ToolCardScaffoldLayout.minimumDisclosureHitHeight >= 32)
}

@MainActor @Test func toolCardEqualityTracksOnlyItsPresentation() {
    let original = tool(id: "read", name: "read", phase: .running)
    var updated = original
    updated.result = .string("Complete output")
    updated.phase = .complete

    #expect(ToolCardView(presentation: original) == ToolCardView(presentation: original))
    #expect(ToolCardView(presentation: original) != ToolCardView(presentation: updated))
}

@Test func collapsedToolGroupStaysCollapsedAsToolsUpdateAndAppend() {
    let state = ToolDisclosureState()
    let initialRows = TranscriptPresentationRow.rows(from: [
        .tool(tool(id: "one", name: "bash", phase: .running)),
    ])
    let groupID = try! #require(toolGroupID(in: initialRows))

    #expect(state.isGroupExpanded(id: groupID))
    state.setGroupExpanded(false, id: groupID)

    let updatedRows = TranscriptPresentationRow.rows(from: [
        .tool(tool(id: "one", name: "bash", phase: .complete)),
        .tool(tool(id: "two", name: "bash", phase: .running)),
    ])
    let updatedGroupID = try! #require(toolGroupID(in: updatedRows))

    #expect(updatedGroupID == groupID)
    #expect(!state.isGroupExpanded(id: updatedGroupID))

    state.collapseAll(ids: ["one", "two"])
    state.expand(ids: ["one"])
    #expect(!state.isGroupExpanded(id: updatedGroupID))
}

@Test func unrelatedDisclosureChangesDoNotInvalidateObservedRows() {
    let state = ToolDisclosureState()
    let groupInvalidations = LockedCounter()
    let toolInvalidations = LockedCounter()

    withObservationTracking {
        _ = state.isGroupExpanded(id: "observed-group")
    } onChange: {
        groupInvalidations.increment()
    }
    withObservationTracking {
        _ = state.isExpanded(id: "observed-tool", defaultValue: true)
    } onChange: {
        toolInvalidations.increment()
    }

    state.setGroupExpanded(false, id: "other-group")
    state.setExpanded(false, id: "other-tool")

    #expect(groupInvalidations.value == 0)
    #expect(toolInvalidations.value == 0)

    state.setGroupExpanded(false, id: "observed-group")
    state.setExpanded(false, id: "observed-tool")

    #expect(groupInvalidations.value == 1)
    #expect(toolInvalidations.value == 1)
}

private func tool(id: String, name: String, phase: ToolPhase) -> ToolPresentation {
    ToolPresentation(
        id: id,
        name: name,
        arguments: .object([:]),
        result: nil,
        phase: phase,
        startDate: Date(timeIntervalSince1970: 1),
        endDate: phase == .running ? nil : Date(timeIntervalSince1970: 2))
}

private func toolGroupID(in rows: [TranscriptPresentationRow]) -> String? {
    for row in rows {
        if case .toolGroup(let group) = row { return group.id }
    }
    return nil
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}
