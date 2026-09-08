import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Test func workingIndicatorOnlyShowsWhileTheRunIsSilent() {
    #expect(TurnActivityView.isAwaitingOutput(runtimeState: .streaming, lastItem: nil))
    #expect(!TurnActivityView.isAwaitingOutput(runtimeState: .idle, lastItem: nil))
    #expect(!TurnActivityView.isAwaitingOutput(runtimeState: .loading, lastItem: nil))
    #expect(!TurnActivityView.isAwaitingOutput(
        runtimeState: .stopped(code: 1, stderrTail: ""),
        lastItem: nil))
}

@Test func aUserMessageStillCountsAsWaitingForOutput() {
    // omp emits the user message as message_start before the assistant answers,
    // so it must not read as output that is already in progress.
    let liveUser = transcriptMessage(role: "user", isFinal: false)
    let finalUser = transcriptMessage(role: "user", isFinal: true)

    #expect(TurnActivityView.isAwaitingOutput(runtimeState: .streaming, lastItem: liveUser))
    #expect(TurnActivityView.isAwaitingOutput(runtimeState: .streaming, lastItem: finalUser))
}

@Test func aStreamingAssistantMessageSuppressesTheIndicator() {
    let streaming = transcriptMessage(role: "assistant", isFinal: false)
    let finished = transcriptMessage(role: "assistant", isFinal: true)

    #expect(!TurnActivityView.isAwaitingOutput(runtimeState: .streaming, lastItem: streaming))
    #expect(TurnActivityView.isAwaitingOutput(runtimeState: .streaming, lastItem: finished))
}

@Test func aRunningToolSuppressesTheIndicatorAndAFinishedOneDoesNot() {
    #expect(!TurnActivityView.isAwaitingOutput(
        runtimeState: .streaming,
        lastItem: .tool(toolPresentation(phase: .running))))
    #expect(TurnActivityView.isAwaitingOutput(
        runtimeState: .streaming,
        lastItem: .tool(toolPresentation(phase: .complete))))
    #expect(TurnActivityView.isAwaitingOutput(
        runtimeState: .streaming,
        lastItem: .tool(toolPresentation(phase: .failed))))
}

@Test func anApprovalCardIsWaitingOnTheUserNotOnTheModel() {
    let approval = TranscriptItem.extensionUI(
        .confirm(id: "approve-1", title: "Run this?", message: "", timeout: nil))

    #expect(!TurnActivityView.isAwaitingOutput(runtimeState: .streaming, lastItem: approval))
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

private func toolPresentation(phase: ToolPhase) -> ToolPresentation {
    ToolPresentation(
        id: "tool-1",
        name: "Read",
        arguments: .object(["path": .string("/tmp/a.txt")]),
        result: phase == .running ? nil : .string("ok"),
        phase: phase,
        startDate: Date(timeIntervalSince1970: 0),
        endDate: phase == .running ? nil : Date(timeIntervalSince1970: 1))
}
