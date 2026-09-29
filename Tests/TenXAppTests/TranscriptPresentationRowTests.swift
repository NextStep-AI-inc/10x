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

@Test func agentGuidanceToggleUpdatesVisibleRows() {
    let items: [TranscriptItem] = [
        .message(userMessage(id: "u1", timestamp: 1)),
        .guidance(GuidancePresentation(
            id: "advisor-1",
            kind: .advisor,
            visibility: .whenEnabled,
            byteCount: 18,
            preview: "Check the probe window.",
            reconcileFingerprint: "advisor")),
        .guidance(GuidancePresentation(
            id: "developer-1",
            kind: .agentGuidance,
            visibility: .whenEnabled,
            byteCount: 42,
            preview: "Plan approved.",
            reconcileFingerprint: "developer")),
        .guidance(GuidancePresentation(
            id: "file-1",
            kind: .referencedFile,
            visibility: .always,
            byteCount: 120,
            preview: "src/Probe.swift",
            reconcileFingerprint: "file")),
        .message(responseMessage(id: "done", stopReason: "stop", completedAt: 4)),
    ]

    let hidden = TranscriptView.renderRows(
        for: items,
        runtimeState: .idle,
        isGroupExpanded: { _ in true },
        showsAgentGuidance: false)
    #expect(hidden.map(\.id) == [
        "message:u1",
        "guidance:file-1",
        "message:done",
        "summary:turn:u1",
    ])

    let shown = TranscriptView.renderRows(
        for: items,
        runtimeState: .idle,
        isGroupExpanded: { _ in true },
        showsAgentGuidance: true)
    #expect(shown.map(\.id) == [
        "message:u1",
        "guidance:advisor-1",
        "guidance:developer-1",
        "guidance:file-1",
        "message:done",
        "summary:turn:u1",
    ])

    let hiddenAgain = TranscriptView.renderRows(
        for: items,
        runtimeState: .idle,
        isGroupExpanded: { _ in true },
        showsAgentGuidance: false)
    #expect(hiddenAgain.map(\.id) == hidden.map(\.id))

    let shownAgain = TranscriptView.renderRows(
        for: items,
        runtimeState: .idle,
        isGroupExpanded: { _ in true },
        showsAgentGuidance: true)
    #expect(shownAgain.map(\.id) == shown.map(\.id))
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
        guard case .summary(_, let state, _, _) = row else { return nil }
        return state
    }
    #expect(summaryStates == [.completed, .failed])
}

@Test func terminalSummaryCarriesOnlyItsTurnsToolReportedFiles() {
    let items: [TranscriptItem] = [
        .message(userMessage(id: "u1", timestamp: 1)),
        .tool(tool(
            id: "write-one",
            name: "write",
            phase: .complete,
            arguments: .object([
                "path": .string("App/One.swift"),
                "content": .string("one"),
            ]))),
        .message(responseMessage(id: "done", stopReason: "stop", completedAt: 4)),
    ]

    let rows = TranscriptView.renderRows(
        for: items, runtimeState: .idle, isGroupExpanded: { _ in true })

    let files = rows.compactMap { row -> [TranscriptTurnFile]? in
        guard case .summary(_, _, _, let files) = row else { return nil }
        return files
    }
    #expect(files == [[TranscriptTurnFile(path: "App/One.swift", toolID: "write-one")]])
}

@Test func turnFileNavigationTargetsTheStableToolRowAndRevealsItFromSlimMode() {
    let file = TranscriptTurnFile(path: "App/One.swift", toolID: "two")
    let request = TranscriptTurnFilesView.navigationRequest(for: file)
    let rows = TranscriptPresentationRow.rows(from: [
        .tool(tool(id: "one", phase: .complete)),
        .tool(tool(id: "two", phase: .complete)),
    ])
    let disclosureState = ToolDisclosureState(mode: .slim)

    #expect(request.rowID == "tool:two")
    #expect(TranscriptView.revealNavigationTarget(
        rowID: request.rowID,
        in: rows,
        disclosureState: disclosureState))
    #expect(disclosureState.isGroupExpanded(id: "tool-group-one"))
    #expect(disclosureState.isExpanded(id: "two", traits: .init(
        isActive: false,
        isError: false,
        opensWhenComplete: false)))
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

@Test func taskDelegateGroupingUsesRegistryKindNotExactSpelling() {
    let delegate = ToolPresentation(
        id: "delegate-task",
        name: "Task",
        arguments: .object(["description": .string("Review wrappers")]),
        result: nil,
        phase: .running,
        startDate: Date(timeIntervalSince1970: 1),
        endDate: nil)
    let worker = subagent(
        id: "worker-one",
        parent: "delegate-task",
        task: "UI review",
        status: .running)
    let rows = TranscriptPresentationRow.rows(from: [
        .tool(delegate),
        .subagent(worker),
    ])

    #expect(rows.contains {
        if case .delegation(let id, _, let workers) = $0 {
            return id == "delegation:delegate-task" && workers.count == 1
        }
        return false
    })
    #expect(!rows.contains { if case .item(.subagent) = $0 { true } else { false } })
}

@Test func delegateRowsPreserveParentOwnership() {
    let delegateA = delegateTool(id: "delegate-a", assignment: "Review tool wrappers", phase: .running)
    let delegateB = delegateTool(id: "delegate-b", assignment: "Audit providers", phase: .complete)
    let workerOne = subagent(
        id: "worker-one",
        parent: "delegate-a",
        task: "UI review",
        status: .running,
        currentTool: "read")
    let workerTwo = subagent(
        id: "worker-two",
        parent: "delegate-a",
        task: "Code review",
        status: .running,
        currentTool: "grep")
    let otherParentWorker = subagent(
        id: "worker-other",
        parent: "delegate-b",
        task: "Provider audit",
        status: .completed,
        result: .string("Providers verified"))
    let orphan = subagent(
        id: "orphan",
        parent: "missing-parent",
        task: "Standalone worker",
        status: .running)
    let misassigned = subagent(
        id: "misassigned",
        parent: "bash-tool",
        task: "Should stay standalone",
        status: .running)

    let groupedRows = TranscriptPresentationRow.rows(from: [
        .tool(delegateA),
        .subagent(workerOne),
        .subagent(workerTwo),
        .tool(delegateB),
        .subagent(otherParentWorker),
        .subagent(orphan),
        .tool(tool(id: "bash-tool", phase: .complete)),
        .subagent(misassigned),
    ])

    let delegationA = try! #require(groupedRows.first {
        if case .delegation(let id, let tool, let workers) = $0 {
            return id == "delegation:delegate-a" && tool.id == "delegate-a" && workers.count == 2
        }
        return false
    })
    if case .delegation(_, _, let workers) = delegationA {
        #expect(workers.map(\.id) == ["worker-one", "worker-two"])
    }

    let delegationB = try! #require(groupedRows.first {
        if case .delegation(let id, _, let workers) = $0 {
            return id == "delegation:delegate-b" && workers.count == 1
        }
        return false
    })
    if case .delegation(_, _, let workers) = delegationB {
        #expect(workers.map(\.id) == ["worker-other"])
    }

    let orphanIDs = groupedRows.compactMap { row -> String? in
        guard case .item(.subagent(let presentation)) = row else { return nil }
        return presentation.id
    }
    #expect(orphanIDs == ["orphan", "misassigned"])
    #expect(!groupedRows.contains {
        if case .item(.subagent(let presentation)) = $0 {
            return presentation.id == "worker-one" || presentation.id == "worker-two"
                || presentation.id == "worker-other"
        }
        return false
    })

    let resultBeforeLifecycle = TranscriptPresentationRow.rows(from: [
        .subagent(subagent(
            id: "early-worker",
            parent: "delegate-a",
            task: "Early worker",
            status: .running,
            result: .string("Finished before parent appeared"))),
        .tool(delegateA),
    ])
    let earlyDelegation = try! #require(resultBeforeLifecycle.first {
        if case .delegation(let id, _, let workers) = $0 {
            return id == "delegation:delegate-a" && workers.count == 1
        }
        return false
    })
    if case .delegation(_, _, let workers) = earlyDelegation {
        #expect(workers.map(\.id) == ["early-worker"])
        #expect(workers[0].resultText == "Finished before parent appeared")
    }

    let updatedWorker = subagent(
        id: "worker-one",
        parent: "delegate-a",
        task: "UI review",
        status: .completed,
        result: .string("Cards match spec"))
    let updatedRows = TranscriptPresentationRow.rows(from: [
        .tool(delegateA),
        .subagent(workerOne),
        .subagent(updatedWorker),
        .subagent(workerTwo),
    ])
    let updatedDelegation = try! #require(updatedRows.first {
        if case .delegation(let id, _, let workers) = $0 { return id == "delegation:delegate-a" }
        return false
    })
    if case .delegation(_, _, let workers) = updatedDelegation {
        #expect(workers.map(\.id) == ["worker-one", "worker-two"])
        #expect(workers[0].status == .completed)
        #expect(workers[0].resultText == "Cards match spec")
    }
    #expect(updatedRows.filter {
        if case .delegation(let id, _, _) = $0 { return id == "delegation:delegate-a" }
        return false
    }.count == 1)
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
    name: String = "bash",
    phase: ToolPhase,
    arguments: JSONValue = .object([:]),
    result: JSONValue? = nil
) -> ToolPresentation {
    ToolPresentation(
        id: id,
        name: name,
        arguments: arguments,
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

private func delegateTool(
    id: String,
    assignment: String,
    phase: ToolPhase
) -> ToolPresentation {
    ToolPresentation(
        id: id,
        name: "task",
        arguments: .object(["description": .string(assignment)]),
        result: nil,
        phase: phase,
        startDate: Date(timeIntervalSince1970: 1),
        endDate: phase == .running ? nil : Date(timeIntervalSince1970: 2))
}

private func subagent(
    id: String,
    parent: String?,
    task: String,
    status: SubagentStatus = .running,
    currentTool: String? = nil,
    result: JSONValue? = nil
) -> SubagentPresentation {
    SubagentPresentation(
        id: id,
        index: 0,
        agent: "reviewer",
        task: task,
        assignment: "Check disclosure",
        description: "Full worker detail stays in the session file.",
        status: status,
        sessionFile: "/tmp/\(id).jsonl",
        parentToolCallID: parent,
        actualModel: "gpt-5.6-sol",
        thinkingLevel: "high",
        modelRole: "review",
        isFallback: false,
        currentTool: currentTool,
        recentTools: [
            SubagentRecentTool(
                name: "read",
                arguments: .object(["path": .string("App/Sessions/TranscriptView.swift")]),
                endMilliseconds: 1_000),
        ],
        recentOutput: ["Checked transcript mapping"],
        toolCount: 6,
        requests: 2,
        tokens: 1_840,
        cost: 0.03,
        durationMilliseconds: 4_200,
        result: result)
}
