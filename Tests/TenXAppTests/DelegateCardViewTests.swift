import Foundation
import OmpKit
import SwiftUI
import Testing
@testable import TenXApp

@Test func delegateWorkerActivitySummaryStaysWithinPreviewBounds() {
    let huge = (1...200).map { "segment-\($0)" }.joined(separator: " ")
    let worker = subagent(
        id: "worker-huge",
        parent: "delegate-a",
        task: "UI review",
        status: .completed,
        result: .string(huge))

    let summary = SubagentPresentation.boundedWorkerActivitySummary(for: worker)

    #expect(summary != nil)
    #expect(Data(summary!.utf8).count <= 512)
    #expect(summary!.split(separator: "\n", omittingEmptySubsequences: false).count <= 6)
    #expect(!summary!.contains(huge))
}

@MainActor
@Test func failedDelegateWithNoWorkersShowsParentFallbackSnapshot() throws {
    let tool = ToolPresentation(
        id: "failed-delegate",
        name: "task",
        arguments: .object(["description": .string("Review tool wrappers")]),
        result: .object(["error": .string("Worker dispatch failed")]),
        phase: .failed,
        startDate: Date(timeIntervalSince1970: 1),
        endDate: Date(timeIntervalSince1970: 2))
    try assertSnapshot(
        DelegateCardView(tool: tool, workers: [])
            .environment(\.toolDisclosureState, ToolDisclosureState(mode: .expanded))
            .frame(width: 720),
        name: "delegate-failed-empty",
        size: CGSize(width: 800, height: 220))
}

private func subagent(
    id: String,
    parent: String?,
    task: String,
    status: SubagentStatus = .running,
    result: JSONValue? = nil
) -> SubagentPresentation {
    SubagentPresentation(
        id: id,
        index: 0,
        agent: "reviewer",
        task: task,
        assignment: nil,
        description: nil,
        status: status,
        sessionFile: "/tmp/\(id).jsonl",
        parentToolCallID: parent,
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
        result: result)
}
