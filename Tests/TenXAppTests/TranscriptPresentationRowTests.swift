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
