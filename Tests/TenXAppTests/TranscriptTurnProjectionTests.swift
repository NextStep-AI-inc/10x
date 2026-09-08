import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Test func consecutiveInputsShareAStableTurnUntilResponseEvidence() throws {
    let first = turnMessage(id: "user-live", baseID: "user-1", role: "user", at: 1)
    let second = turnMessage(id: "user-2", role: "user", at: 2)
    let beforeResponse = TranscriptTurnProjection.sections(
        from: [.message(first)], runtimeState: .streaming)
    let batched = TranscriptTurnProjection.sections(
        from: [.message(first), .notice(id: "notice", level: "info", message: "Queued"), .message(second)],
        runtimeState: .streaming)

    #expect(beforeResponse.map(\.id) == ["turn:user-1"])
    #expect(batched.map(\.id) == ["turn:user-1"])
    #expect(batched[0].items.map(\.id) == ["user-live", "notice", "user-2"])

    let responded = batched[0].items + [.message(turnMessage(
        id: "assistant-1", role: "assistant", at: 3, completedAt: 4,
        stopReason: "stop", isFinal: true))]
    let sections = TranscriptTurnProjection.sections(
        from: responded + [.message(turnMessage(id: "user-3", role: "user", at: 5))],
        runtimeState: .streaming)

    #expect(sections.map(\.id) == ["turn:user-1", "turn:user-3"])
    #expect(sections[0].state == .completed)
    #expect(sections[1].state == .working)
}

@Test func preambleStaysStandaloneAndNoticesDoNotSplitInputs() {
    let items: [TranscriptItem] = [
        .threadStart(id: "thread", date: nil),
        .notice(id: "ready", level: "info", message: "Ready"),
        .message(turnMessage(id: "u1", role: "user", at: 1)),
        .annotation(TranscriptAnnotation(
            id: "annotation", kind: .mode, title: "Mode", detail: nil,
            timestamp: nil, tone: .neutral)),
        .message(turnMessage(id: "u2", role: "user", at: 2)),
    ]

    let sections = TranscriptTurnProjection.sections(from: items, runtimeState: .idle)

    #expect(sections.map(\.id) == ["transcript-preamble", "turn:u1"])
    #expect(sections[0].items.map(\.id) == ["thread", "ready"])
    #expect(sections[0].state == nil)
    #expect(sections[1].items.map(\.id) == ["u1", "annotation", "u2"])
    #expect(sections[1].state == .unknown)
}

@Test func equivalentLiveAndHistorySegmentsKeepTheSameTurnIDAndDuration() {
    let user = turnMessage(id: "user-segment", baseID: "stable-user", role: "user", at: 1)
    let live = turnMessage(
        id: "assistant-live", baseID: "assistant-base", role: "assistant", at: 4,
        completedAt: 8, stopReason: "stop", isFinal: true)
    let history = turnMessage(
        id: "assistant-history", baseID: "assistant-base", role: "assistant", at: 4,
        completedAt: 8, stopReason: "stop", isFinal: true)

    let liveTurn = TranscriptTurnProjection.sections(
        from: [.message(user), .message(live)], runtimeState: .idle)[0]
    let historyTurn = TranscriptTurnProjection.sections(
        from: [.message(user), .message(history)], runtimeState: .idle)[0]

    #expect(liveTurn.id == historyTurn.id)
    #expect(liveTurn.duration == 4)
    #expect(historyTurn.duration == liveTurn.duration)
}

@Test func responseDurationUsesTheLoopBoundsWithoutQueuedWaitOrRepeatedSegments() {
    let items: [TranscriptItem] = [
        .message(turnMessage(id: "user", role: "user", at: 1)),
        .message(turnMessage(
            id: "a-live", baseID: "a", role: "assistant", at: 10,
            completedAt: 12, stopReason: "toolUse")),
        .tool(turnTool(id: "tool", phase: .complete, start: 12, end: 15)),
        .message(turnMessage(
            id: "a-final", baseID: "a", role: "assistant", at: 10,
            completedAt: 16, stopReason: "stop", isFinal: true)),
    ]

    let turn = TranscriptTurnProjection.sections(from: items, runtimeState: .idle)[0]

    #expect(turn.duration == 6)
}

@Test func responseDurationIsAbsentWithoutAReliableCompletion() {
    let turn = TranscriptTurnProjection.sections(from: [
        .message(turnMessage(id: "user", role: "user", at: 1)),
        .message(turnMessage(
            id: "assistant", role: "assistant", at: 3,
            stopReason: "stop", isFinal: true)),
    ], runtimeState: .idle)[0]

    #expect(turn.state == .completed)
    #expect(turn.duration == nil)
}

@Test func activeStateScansTheWholeFinalTurnAndPrioritizesPendingInput() {
    let user = TranscriptItem.message(turnMessage(id: "user", role: "user", at: 1))
    let running = TranscriptItem.tool(turnTool(id: "running", phase: .running, start: 2))
    let complete = TranscriptItem.tool(turnTool(id: "complete", phase: .complete, start: 3, end: 4))

    let tools = TranscriptTurnProjection.sections(
        from: [user, running, complete], runtimeState: .idle)[0]
    #expect(tools.state == .working)

    let pending = TranscriptTurnProjection.sections(
        from: [user, running, .extensionUI(.confirm(
            id: "approval", title: "Continue?", message: "", timeout: nil))],
        runtimeState: .streaming)[0]
    #expect(pending.state == .pendingInput)
}

@Test func activeSubagentKeepsTheFinalTurnWorking() {
    let turn = TranscriptTurnProjection.sections(from: [
        .message(turnMessage(id: "user", role: "user", at: 1)),
        .subagent(turnSubagent(status: .running)),
    ], runtimeState: .idle)[0]

    #expect(turn.state == .working)
}

@Test func terminalAssistantOutcomeOverridesEarlierRecoverableToolFailure() {
    let prefix: [TranscriptItem] = [
        .message(turnMessage(id: "user", role: "user", at: 1)),
        .tool(turnTool(id: "tool", phase: .failed, start: 2, end: 3)),
    ]
    let success = TranscriptTurnProjection.sections(from: prefix + [
        .message(turnMessage(
            id: "success", role: "assistant", at: 4, completedAt: 5,
            stopReason: "stop", isFinal: true)),
    ], runtimeState: .idle)[0]
    let failure = TranscriptTurnProjection.sections(from: prefix + [
        .message(turnMessage(
            id: "failure", role: "assistant", at: 4, completedAt: 5,
            stopReason: "error", isFinal: true)),
    ], runtimeState: .idle)[0]
    let stopped = TranscriptTurnProjection.sections(from: prefix + [
        .message(turnMessage(
            id: "stopped", role: "assistant", at: 4, completedAt: 5,
            stopReason: "aborted", isFinal: true)),
    ], runtimeState: .idle)[0]

    #expect(success.state == .completed)
    #expect(failure.state == .failed)
    #expect(stopped.state == .stopped)
}

@Test func nonterminalToolUseAndLengthDoNotCompleteAResponseTurn() {
    let user = TranscriptItem.message(turnMessage(id: "user", role: "user", at: 1))
    let toolUse = TranscriptItem.message(turnToolUseMessage(id: "step", toolID: "tool", at: 2))

    let running = TranscriptTurnProjection.sections(from: [
        user, toolUse, .tool(turnTool(id: "tool", phase: .running, start: 3)),
    ], runtimeState: .idle)[0]
    let failed = TranscriptTurnProjection.sections(from: [
        user, toolUse, .tool(turnTool(id: "tool", phase: .failed, start: 3, end: 4)),
    ], runtimeState: .idle)[0]
    let finished = TranscriptTurnProjection.sections(from: [
        user, toolUse, .tool(turnTool(id: "tool", phase: .complete, start: 3, end: 4)),
    ], runtimeState: .idle)[0]
    let length = TranscriptTurnProjection.sections(from: [
        user,
        .message(turnMessage(
            id: "length", role: "assistant", at: 2, completedAt: 3,
            stopReason: "length", isFinal: true)),
    ], runtimeState: .idle)[0]

    #expect(running.state == .working)
    #expect(failed.state == .failed)
    #expect(finished.state == .interrupted)
    #expect(length.state == .interrupted)
}

@Test func packedTerminalStopCompletesWhenItsToolResultsArePresent() {
    let turn = TranscriptTurnProjection.sections(from: [
        .message(turnMessage(id: "user", role: "user", at: 1)),
        .message(turnPackedStopMessage(id: "stop", toolID: "tool", at: 2, completedAt: 3)),
        .tool(turnTool(id: "tool", phase: .complete, start: 3, end: 4)),
    ], runtimeState: .idle)[0]

    #expect(turn.state == .completed)
}

@Test func settledTerminalResponseOverridesALeftoverRunningTool() {
    let prefix: [TranscriptItem] = [
        .message(turnMessage(id: "user", role: "user", at: 1)),
        .tool(turnTool(id: "tool", phase: .running, start: 2)),
    ]
    let stopped = TranscriptTurnProjection.sections(from: prefix + [
        .message(turnMessage(
            id: "stopped", role: "assistant", at: 3, completedAt: 4,
            stopReason: "aborted", isFinal: true)),
    ], runtimeState: .idle)[0]
    let active = TranscriptTurnProjection.sections(from: prefix + [
        .message(turnMessage(
            id: "stopping", role: "assistant", at: 3, completedAt: 4,
            stopReason: "aborted", isFinal: true)),
    ], runtimeState: .streaming)[0]

    #expect(stopped.state == .stopped)
    #expect(active.state == .working)
}

@Test func interruptedToolAndAbortedTerminalAgreeOnStoppedTurnState() {
    let turn = TranscriptTurnProjection.sections(from: [
        .message(turnMessage(id: "user", role: "user", at: 1)),
        .tool(turnTool(id: "tool", phase: .interrupted, start: 2, end: 3)),
        .message(turnMessage(
            id: "stopped", role: "assistant", at: 3, completedAt: 4,
            stopReason: "aborted", isFinal: true)),
    ], runtimeState: .stopped(code: nil, stderrTail: ""))[0]

    #expect(turn.state == .stopped)
    #expect(turn.duration == 2)
}

@Test func failedToolsInterruptedTurnsAndIncompleteHistoryRemainDistinct() {
    let user = TranscriptItem.message(turnMessage(id: "user", role: "user", at: 1))
    let failed = TranscriptTurnProjection.sections(from: [
        user, .tool(turnTool(id: "tool", phase: .failed, start: 2, end: 3)),
    ], runtimeState: .idle)[0]
    let interrupted = TranscriptTurnProjection.sections(from: [
        user,
        .tool(turnTool(id: "tool", phase: .complete, start: 2, end: 3)),
        .message(turnMessage(id: "next", role: "user", at: 4)),
    ], runtimeState: .idle)[0]
    let incomplete = TranscriptTurnProjection.sections(from: [user], runtimeState: .idle)[0]
    let nonterminalAssistant = TranscriptTurnProjection.sections(from: [
        user,
        .message(turnMessage(
            id: "assistant", role: "assistant", at: 2,
            completedAt: 3, isFinal: true)),
    ], runtimeState: .idle)[0]

    #expect(failed.state == .failed)
    #expect(interrupted.state == .interrupted)
    #expect(incomplete.state == .unknown)
    #expect(nonterminalAssistant.state == .unknown)
}

private func turnMessage(
    id: String,
    baseID: String? = nil,
    role: String,
    at: TimeInterval,
    completedAt: TimeInterval? = nil,
    stopReason: String? = nil,
    isFinal: Bool = false
) -> TranscriptMessage {
    var raw: [String: JSONValue] = [
        "role": .string(role),
        "content": .string(role == "user" ? "Question" : "Answer"),
        "timestamp": .double(at * 1_000),
    ]
    if let completedAt { raw["completedAt"] = .double(completedAt * 1_000) }
    if let stopReason { raw["stopReason"] = .string(stopReason) }
    return TranscriptMessage(
        id: id,
        raw: .object(raw),
        isFinal: isFinal,
        renderLineageKey: .base(messageID: baseID ?? id))
}

private func turnTool(
    id: String,
    phase: ToolPhase,
    start: TimeInterval,
    end: TimeInterval? = nil
) -> ToolPresentation {
    ToolPresentation(
        id: id,
        name: "read",
        arguments: .object([:]),
        result: phase == .running ? nil : .string("done"),
        phase: phase,
        startDate: Date(timeIntervalSince1970: start),
        endDate: end.map(Date.init(timeIntervalSince1970:)))
}

private func turnToolUseMessage(
    id: String,
    toolID: String,
    at: TimeInterval
) -> TranscriptMessage {
    TranscriptMessage(
        id: id,
        raw: .object([
            "role": .string("assistant"),
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string("I will inspect it."),
                ]),
                .object([
                    "type": .string("toolCall"),
                    "id": .string(toolID),
                ]),
            ]),
            "timestamp": .double(at * 1_000),
            "completedAt": .double((at + 1) * 1_000),
            "stopReason": .string("toolUse"),
        ]),
        isFinal: true)
}

private func turnPackedStopMessage(
    id: String,
    toolID: String,
    at: TimeInterval,
    completedAt: TimeInterval
) -> TranscriptMessage {
    TranscriptMessage(
        id: id,
        raw: .object([
            "role": .string("assistant"),
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string("Done."),
                ]),
                .object([
                    "type": .string("toolCall"),
                    "id": .string(toolID),
                ]),
            ]),
            "timestamp": .double(at * 1_000),
            "completedAt": .double(completedAt * 1_000),
            "stopReason": .string("stop"),
        ]),
        isFinal: true)
}

private func turnSubagent(status: SubagentStatus) -> SubagentPresentation {
    SubagentPresentation(
        id: "subagent", index: 0, agent: "worker", task: "Work",
        assignment: nil, description: nil, status: status, sessionFile: nil,
        parentToolCallID: nil, actualModel: nil, thinkingLevel: nil, modelRole: nil,
        isFallback: false, currentTool: nil, recentTools: [], recentOutput: [],
        toolCount: 0, requests: nil, tokens: nil, cost: nil,
        durationMilliseconds: 0, result: nil)
}
