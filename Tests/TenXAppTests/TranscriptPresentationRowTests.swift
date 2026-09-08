import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Test func consecutiveToolsFormOneGroupAndAssistantContentSplitsGroups() {
    let rows = TranscriptPresentationRow.rows(from: [
        .message(message(id: "before")),
        .tool(tool(id: "one", phase: .complete)),
        .tool(tool(id: "two", phase: .running)),
        .message(message(id: "after")),
        .tool(tool(id: "three", phase: .failed)),
    ])

    #expect(rows.map(\.id) == [
        "message:before",
        "tool-group-one",
        "tool:one",
        "tool:two",
        "message:after",
        "tool-group-three",
        "tool:three",
    ])
    #expect(toolIDs(in: rows) == [["one", "two"], ["three"]])
    #expect(toolPhases(in: rows) == [.running, .failed])
}

@Test func interruptedToolMakesMixedCompletedGroupInterrupted() {
    let rows = TranscriptPresentationRow.rows(from: [
        .tool(tool(id: "completed", phase: .complete)),
        .tool(tool(id: "stopped", phase: .interrupted)),
    ])

    #expect(toolPhases(in: rows) == [.interrupted])
}

@Test func groupedToolsAreIndependentRowsThatDisappearWhenTheirGroupCollapses() {
    let rows = TranscriptPresentationRow.rows(from: [
        .message(message(id: "before")),
        .tool(tool(id: "one", phase: .complete)),
        .tool(tool(id: "two", phase: .complete)),
        .message(message(id: "after")),
    ])

    #expect(rows.map(\.id) == [
        "message:before",
        "tool-group-one",
        "tool:one",
        "tool:two",
        "message:after",
    ])

    let collapsedRows = TranscriptPresentationRow.visibleRows(
        from: rows,
        isGroupExpanded: { $0 != "tool-group-one" })

    #expect(collapsedRows.map(\.id) == [
        "message:before",
        "tool-group-one",
        "message:after",
    ])
}

@Test func hiddenGroupedToolResolvesToItsVisibleGroupForRestoration() {
    let rows = TranscriptPresentationRow.rows(from: [
        .tool(tool(id: "one", phase: .complete)),
        .tool(tool(id: "two", phase: .complete)),
    ])

    #expect(TranscriptView.groupID(containing: "tool:two", in: rows) == "tool-group-one")
    #expect(TranscriptView.groupID(containing: "message:missing", in: rows) == nil)
}

@Test func noticeEndsToolGroupRatherThanBeingAbsorbed() {
    let rows = TranscriptPresentationRow.rows(from: [
        .tool(tool(id: "before", phase: .running)),
        .notice(id: "notice", level: "info", message: "A boundary"),
        .tool(tool(id: "after", phase: .complete)),
    ])

    #expect(rows.map(\.id) == [
        "tool-group-before",
        "tool:before",
        "notice:notice",
        "tool-group-after",
        "tool:after",
    ])
    #expect(toolIDs(in: rows) == [["before"], ["after"]])
}

@Test func earlierToolUpdateChangesObservationWithoutInvalidatingTheFinalRow() {
    let finalTool = tool(id: "two", phase: .running)
    let initialRows = TranscriptPresentationRow.rows(from: [
        .tool(tool(id: "one", phase: .running)),
        .tool(finalTool),
    ])
    let updatedRows = TranscriptPresentationRow.rows(from: [
        .tool(tool(id: "one", phase: .complete, result: .string("Completed"))),
        .tool(finalTool),
    ])
    let initialLastRow = try! #require(initialRows.last)
    let updatedLastRow = try! #require(updatedRows.last)

    #expect(initialRows != updatedRows)
    #expect(initialLastRow == updatedLastRow)
    #expect(initialLastRow.id == "tool:two")
}

@Test func followObservationTracksMiddleToolGroupChangesWhenLaterMessageIsLast() {
    let finalMessage = message(id: "after")
    let initialItems: [TranscriptItem] = [
        .message(message(id: "before")),
        .tool(tool(id: "one", phase: .running)),
        .message(finalMessage),
    ]
    let updatedItems: [TranscriptItem] = [
        .message(message(id: "before")),
        .tool(tool(id: "one", phase: .complete, result: .string("Completed"))),
        .message(finalMessage),
    ]
    let initialObservation = TranscriptView.followObservation(for: initialItems)
    let updatedObservation = TranscriptView.followObservation(for: updatedItems)
    let initialLastRow = try! #require(initialObservation.last)
    let updatedLastRow = try! #require(updatedObservation.last)

    #expect(initialObservation != updatedObservation)
    #expect(initialLastRow == updatedLastRow)
    #expect(initialLastRow.id == "message:after")
    #expect(initialObservation.map(\.id) == [
        "message:before",
        "tool-group-one",
        "tool:one",
        "message:after",
    ])
    #expect(initialObservation[1] != updatedObservation[1])
}

@Test func automaticTranscriptFollowingNeverStacksAnimations() {
    #expect(!TranscriptView.shouldAnimateScroll(
        intent: .automatic,
        isReduceMotionEnabled: false))
    #expect(TranscriptView.shouldAnimateScroll(
        intent: .explicit,
        isReduceMotionEnabled: false))
    #expect(!TranscriptView.shouldAnimateScroll(
        intent: .explicit,
        isReduceMotionEnabled: true))
}

@Test func transcriptRenderRowsKeepContentIDsAndAppendOnlyTerminalSummaries() {
    let completed = responseMessage(id: "done", stopReason: "stop", completedAt: 4)
    let failed = responseMessage(id: "failed", stopReason: "error", completedAt: 8)
    let items: [TranscriptItem] = [
        .message(userMessage(id: "u1", timestamp: 1)),
        .tool(tool(id: "one", phase: .complete)),
        .message(completed),
        .message(userMessage(id: "u2", timestamp: 5)),
        .message(failed),
    ]

    let rows = TranscriptView.renderRows(
        for: items, runtimeState: .idle, isGroupExpanded: { _ in true })

    #expect(rows.map(\.id) == [
        "message:u1", "tool-group-one", "tool:one", "message:done", "summary:turn:u1",
        "message:u2", "message:failed", "summary:turn:u2",
    ])
    let summaryStates: [TranscriptTurnState] = rows.compactMap { row in
        guard case .summary(_, let state, _) = row else { return nil }
        return state
    }
    #expect(summaryStates == [.completed, .failed])
}

@Test func incompleteAndActiveTurnsDoNotReceiveSummaryRows() {
    let items: [TranscriptItem] = [
        .message(userMessage(id: "u1", timestamp: 1)),
        .message(responseMessage(id: "done", stopReason: "stop", completedAt: 2)),
        .message(userMessage(id: "u2", timestamp: 3)),
    ]

    let rows = TranscriptView.renderRows(
        for: items, runtimeState: .streaming, isGroupExpanded: { _ in true })

    #expect(rows.map(\.id) == [
        "message:u1", "message:done", "summary:turn:u1", "message:u2",
    ])
}

@Test func turnSummaryLabelsStateAndReliableDuration() {
    #expect(TranscriptTurnSummaryView.label(state: .completed, duration: 6.4) == "Completed · 6.4s")
    #expect(TranscriptTurnSummaryView.label(state: .completed, duration: nil) == "Completed")
    #expect(TranscriptTurnSummaryView.label(state: .interrupted, duration: nil) == "Stopped")
    #expect(TranscriptTurnSummaryView.label(state: .stopped, duration: nil) == "Stopped")
    #expect(TranscriptTurnSummaryView.label(state: .failed, duration: nil) == "Failed")
}

private func message(id: String) -> TranscriptMessage {
    TranscriptMessage(
        id: id,
        raw: .object([
            "role": .string("assistant"),
            "content": .string("Message \(id)"),
        ]),
        timestamp: Date(timeIntervalSince1970: 1),
        isFinal: true)
}

private func userMessage(id: String, timestamp: TimeInterval) -> TranscriptMessage {
    TranscriptMessage(
        id: id,
        raw: .object([
            "role": .string("user"),
            "content": .string("Question"),
            "timestamp": .double(timestamp * 1_000),
        ]),
        isFinal: true)
}

private func responseMessage(
    id: String,
    stopReason: String,
    completedAt: TimeInterval
) -> TranscriptMessage {
    TranscriptMessage(
        id: id,
        raw: .object([
            "role": .string("assistant"),
            "content": .string("Answer"),
            "timestamp": .double((completedAt - 1) * 1_000),
            "completedAt": .double(completedAt * 1_000),
            "stopReason": .string(stopReason),
        ]),
        isFinal: true)
}

private func tool(
    id: String,
    phase: ToolPhase,
    result: JSONValue? = nil
) -> ToolPresentation {
    ToolPresentation(
        id: id,
        name: "bash",
        arguments: .object([:]),
        result: result,
        phase: phase,
        startDate: Date(timeIntervalSince1970: 1),
        endDate: phase == .running ? nil : Date(timeIntervalSince1970: 2))
}

private func toolIDs(in rows: [TranscriptPresentationRow]) -> [[String]] {
    rows.compactMap { row in
        guard case .toolGroup(let group) = row else { return nil }
        return group.tools.map(\.id)
    }
}

private func toolPhases(in rows: [TranscriptPresentationRow]) -> [ToolPhase] {
    rows.compactMap { row in
        guard case .toolGroup(let group) = row else { return nil }
        return group.phase
    }
}
