import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Test func workingIndicatorOnlyShowsWhileTheRunIsSilent() {
    #expect(TurnActivityView.isAwaitingOutput(runtimeState: .streaming, items: []))
    #expect(!TurnActivityView.isAwaitingOutput(runtimeState: .idle, items: []))
    #expect(!TurnActivityView.isAwaitingOutput(runtimeState: .loading, items: []))
    #expect(!TurnActivityView.isAwaitingOutput(
        runtimeState: .stopped(code: 1, stderrTail: ""),
        items: []))
}

@Test func aUserMessageStillCountsAsWaitingForOutput() {
    // omp emits the user message as message_start before the assistant answers,
    // so it must not read as output that is already in progress.
    let liveUser = transcriptMessage(role: "user", isFinal: false)
    let finalUser = transcriptMessage(role: "user", isFinal: true)

    #expect(TurnActivityView.isAwaitingOutput(runtimeState: .streaming, items: [liveUser]))
    #expect(TurnActivityView.isAwaitingOutput(runtimeState: .streaming, items: [finalUser]))
}

@Test func aStreamingAssistantMessageSuppressesTheIndicator() {
    let streaming = transcriptMessage(role: "assistant", isFinal: false)
    let finished = transcriptMessage(role: "assistant", isFinal: true)

    #expect(!TurnActivityView.isAwaitingOutput(runtimeState: .streaming, items: [streaming]))
    #expect(TurnActivityView.isAwaitingOutput(runtimeState: .streaming, items: [finished]))
}

@Test func aRunningToolSuppressesTheIndicatorAndAFinishedOneDoesNot() {
    #expect(!TurnActivityView.isAwaitingOutput(
        runtimeState: .streaming,
        items: [.tool(toolPresentation(phase: .running))]))
    #expect(TurnActivityView.isAwaitingOutput(
        runtimeState: .streaming,
        items: [.tool(toolPresentation(phase: .complete))]))
    #expect(TurnActivityView.isAwaitingOutput(
        runtimeState: .streaming,
        items: [.tool(toolPresentation(phase: .failed))]))
}

@Test func aRunningToolEarlierInTheActiveTurnSuppressesDuplicateActivity() {
    let items: [TranscriptItem] = [
        transcriptMessage(role: "user", isFinal: true),
        .tool(toolPresentation(id: "running", phase: .running)),
        .tool(toolPresentation(id: "complete", phase: .complete)),
    ]

    #expect(!TurnActivityView.isAwaitingOutput(runtimeState: .streaming, items: items))
}

@Test func aCompletedToolAfterPackedAssistantTextResumesActivity() {
    let user = transcriptMessage(role: "user", isFinal: true)
    let completeTool = TranscriptItem.tool(toolPresentation(phase: .complete))
    let liveMessage = transcriptMessage(role: "assistant", isFinal: false)

    #expect(TurnActivityView.isAwaitingOutput(
        runtimeState: .streaming,
        items: [user, liveMessage, completeTool]))
    #expect(!TurnActivityView.isAwaitingOutput(
        runtimeState: .streaming,
        items: [user, completeTool, liveMessage]))
}

@Test func anActiveSubagentEarlierInTheTurnSuppressesDuplicateActivity() {
    let user = transcriptMessage(role: "user", isFinal: true)
    let completeTool = TranscriptItem.tool(toolPresentation(phase: .complete))

    #expect(!TurnActivityView.isAwaitingOutput(
        runtimeState: .streaming,
        items: [user, .subagent(activitySubagent()), completeTool]))
}

@Test func anApprovalCardIsWaitingOnTheUserNotOnTheModel() {
    let approval = TranscriptItem.extensionUI(
        .confirm(id: "approve-1", title: "Run this?", message: "", timeout: nil))

    #expect(!TurnActivityView.isAwaitingOutput(runtimeState: .streaming, items: [approval]))
}

private func transcriptMessage(role: String, isFinal: Bool) -> TranscriptItem {
    .message(TranscriptMessage(
        id: "message-\(role)-\(isFinal)",
        raw: .object([
            "role": .string(role),
            "content": .string("hello"),
        ]),
        isFinal: isFinal))
}

private func toolPresentation(id: String = "tool-1", phase: ToolPhase) -> ToolPresentation {
    ToolPresentation(
        id: id,
        name: "Read",
        arguments: .object(["path": .string("/tmp/a.txt")]),
        result: phase == .running ? nil : .string("ok"),
        phase: phase,
        startDate: Date(timeIntervalSince1970: 0),
        endDate: phase == .running ? nil : Date(timeIntervalSince1970: 1))
}

private func activitySubagent() -> SubagentPresentation {
    SubagentPresentation(
        id: "subagent", index: 0, agent: "worker", task: "Inspect",
        assignment: nil, description: nil, status: .running, sessionFile: nil,
        parentToolCallID: nil, actualModel: nil, thinkingLevel: nil, modelRole: nil,
        isFallback: false, currentTool: nil, recentTools: [], recentOutput: [],
        toolCount: 0, requests: nil, tokens: nil, cost: nil,
        durationMilliseconds: 0, result: nil)
}
