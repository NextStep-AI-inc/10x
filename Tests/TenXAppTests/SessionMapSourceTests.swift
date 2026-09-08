import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Test func sessionMapDigestDeduplicatesSplitMessagesAndToolResults() {
    let raw: JSONValue = .object([
        "role": .string("assistant"),
        "content": .string("First segment"),
        "stopReason": .string("toolUse"),
    ])
    let first = TranscriptMessage(
        id: "assistant-1",
        raw: raw,
        isFinal: true,
        renderLineageKey: .init(
            baseMessageID: "assistant-1",
            precedingToolCallID: nil,
            followingToolCallID: "tool-1"))
    let tool = ToolPresentation(
        id: "tool-1",
        name: "edit",
        arguments: .object(["path": .string("App.swift")]),
        result: .object(["output": .string("done")]),
        phase: .complete,
        startDate: .distantPast,
        endDate: .distantPast)
    let second = TranscriptMessage(
        id: "assistant-1-segment-1",
        raw: .object([
            "role": .string("assistant"),
            "content": .string("Second segment"),
            "stopReason": .string("stop"),
        ]),
        isFinal: true,
        showsResponseMetadata: false,
        renderLineageKey: .init(
            baseMessageID: "assistant-1",
            precedingToolCallID: "tool-1",
            followingToolCallID: nil))

    let source = SessionMapSourceAdapter.make(
        items: [.message(first), .tool(tool), .message(second)],
        sessionKey: "session",
        lineage: "lineage")

    #expect(source.entries.map(\.id) == ["assistant-1", "tool-1"])
    #expect(source.finishedTurnIDs == ["assistant-1"])
}

@Test func sessionMapWarmAndColdSourceAgree() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appending(path: "session.jsonl")
    try Data("""
    {"type":"session","version":3,"id":"s","timestamp":"2026-08-24T20:00:00.000Z","cwd":"/tmp"}
    {"type":"message","id":"u1","parentId":null,"timestamp":"2026-08-24T20:00:01.000Z","message":{"role":"user","content":"Build the map","timestamp":1787601601000}}
    {"type":"message","id":"a1","parentId":"u1","timestamp":"2026-08-24T20:00:02.000Z","message":{"role":"assistant","content":"Map ready","timestamp":1787601602000,"stopReason":"stop"}}
    """.utf8).write(to: file)
    let coldHistory = try #require(try await SessionTimelineLoader().load(path: file.path))
    let cold = SessionMapSourceAdapter.make(
        items: coldHistory.items,
        sessionKey: "session",
        lineage: "lineage")

    let live: [TranscriptItem] = [
        .message(TranscriptMessage(
            id: "u1",
            raw: .object([
                "role": .string("user"),
                "content": .string("Build the map"),
                "timestamp": .double(1_787_601_601_000),
            ]),
            isFinal: true)),
        .message(TranscriptMessage(
            id: "a1",
            raw: .object([
                "role": .string("assistant"),
                "content": .string("Map ready"),
                "timestamp": .double(1_787_601_602_000),
                "stopReason": .string("stop"),
            ]),
            isFinal: true)),
    ]
    let warm = SessionMapSourceAdapter.make(
        items: live,
        sessionKey: "session",
        lineage: "lineage")

    #expect(warm == cold)
    #expect(cold.finishedTurnIDs == ["a1"])
}

@Test func sessionMapSourceExcludesHiddenPrivateAndImagePayloads() {
    let hidden = TranscriptMessage(
        id: "hidden",
        raw: .object([
            "role": .string("hookMessage"),
            "display": .bool(false),
            "content": .string("private harness descriptor"),
        ]),
        isFinal: true)
    let visible = TranscriptMessage(
        id: "visible",
        raw: .object([
            "role": .string("assistant"),
            "content": .array([
                .object(["type": .string("thinking"), "text": .string("secret reasoning")]),
                .object(["type": .string("image"), "data": .string("c2VjcmV0LWJ5dGVz")]),
                .object(["type": .string("text"), "text": .string("Public result")]),
            ]),
            "stopReason": .string("stop"),
        ]),
        isFinal: true)

    let source = SessionMapSourceAdapter.make(
        items: [.message(hidden), .message(visible)],
        sessionKey: "session",
        lineage: "lineage")

    #expect(source.entries.map(\.id) == ["visible"])
    #expect(source.entries.first?.text == "Public result")
    #expect(!source.entries.first!.contentFingerprint.contains("secret"))
}

@Test func sessionMapSourceUsesOnlyAuthoritativeStructuredStatusEvidence() {
    let edit = ToolPresentation(
        id: "edit-1",
        name: "edit",
        arguments: .object(["path": .string("App/View.swift")]),
        result: .object(["output": .string("updated")]),
        phase: .complete,
        startDate: .distantPast,
        endDate: .distantPast)
    let task = ToolPresentation(
        id: "task-1",
        name: "task",
        arguments: .object(["title": .string("Build map source")]),
        result: .object(["details": .object(["status": .string("complete")])]),
        phase: .complete,
        startDate: .distantPast,
        endDate: .distantPast)
    let staleTodoArguments = ToolPresentation(
        id: "todo-1",
        name: "todo",
        arguments: .object(["todos": .array([
            .object(["content": .string("Unconfirmed task"), "status": .string("completed")]),
        ])]),
        result: nil,
        phase: .complete,
        startDate: .distantPast,
        endDate: .distantPast)
    let failedTodo = ToolPresentation(
        id: "todo-failed",
        name: "todo",
        arguments: .object(["todos": .array([
            .object(["content": .string("Failed update"), "status": .string("completed")]),
        ])]),
        result: .object(["error": .string("Could not update todos")]),
        phase: .failed,
        startDate: .distantPast,
        endDate: .distantPast)
    let acknowledgedTodo = ToolPresentation(
        id: "todo-acknowledged",
        name: "todo",
        arguments: .object(["todos": .array([
            .object(["content": .string("Requested only"), "status": .string("completed")]),
        ])]),
        result: .object(["output": .string("ok")]),
        phase: .complete,
        startDate: .distantPast,
        endDate: .distantPast)
    let returnedTodo = ToolPresentation(
        id: "todo-returned",
        name: "todo",
        arguments: .object(["todos": .array([
            .object(["content": .string("Requested only"), "status": .string("completed")]),
        ])]),
        result: .object(["details": .object(["todos": .array([
            .object(["content": .string("Confirmed task"), "status": .string("completed")]),
        ])])]),
        phase: .complete,
        startDate: .distantPast,
        endDate: .distantPast)

    let source = SessionMapSourceAdapter.make(
        items: [
            .tool(edit),
            .tool(task),
            .tool(staleTodoArguments),
            .tool(failedTodo),
            .tool(acknowledgedTodo),
            .tool(returnedTodo),
        ],
        sessionKey: "session",
        lineage: "lineage")

    #expect(source.statusEvidence == [
        SessionMapStatusEvidence(
            sourceRef: "task-1",
            status: .done,
            target: .label("Build map source")),
        SessionMapStatusEvidence(
            sourceRef: "todo-returned",
            status: .done,
            target: .label("Confirmed task")),
    ])
}
