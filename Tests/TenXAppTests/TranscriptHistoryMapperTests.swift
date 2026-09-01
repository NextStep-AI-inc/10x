import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Test func historyMapperPreservesThreadModelModeAndToolOrder() throws {
    let header = SessionHeader(
        id: "session-1",
        cwd: "/tmp/project",
        timestamp: "2026-08-24T20:00:00.000Z",
        version: 3,
        title: "Transcript",
        titleSource: "user",
        parentSession: nil)
    let entries: [SessionEntry] = [
        .modelChange(
            base: historyBase("model-1", nil, 1),
            selection: SessionModelSelection(
                model: "openai-codex/gpt-5.6-sol",
                role: "default",
                resolvedModelIsFallback: false)),
        .modeChange(
            base: historyBase("mode-1", "model-1", 2),
            selection: SessionModeSelection(mode: "plan", data: nil)),
        .message(
            base: historyBase("user-1", "mode-1", 3),
            message: try historyJSON(#"{"role":"user","content":[{"type":"text","text":"Update App.swift"}],"timestamp":1787601603000}"#)),
        .message(
            base: historyBase("assistant-1", "user-1", 4),
            message: try historyJSON(#"{"role":"assistant","provider":"openai-codex","model":"gpt-5.6-sol","content":[{"type":"text","text":"I will update it."},{"type":"toolCall","id":"tool-1","name":"edit","arguments":{"path":"/tmp/project/App.swift"}},{"type":"text","text":"The update is complete."}],"timestamp":1787601604000,"stopReason":"toolUse"}"#)),
        .message(
            base: historyBase("result-1", "assistant-1", 5),
            message: try historyJSON(#"{"role":"toolResult","toolCallId":"tool-1","toolName":"edit","content":[{"type":"text","text":"done"}],"timestamp":1787601605000,"isError":false}"#)),
    ]

    let history = TranscriptHistoryMapper.map(header: header, path: entries)

    #expect(history.items.map(\.id) == [
        "thread-start-session-1",
        "user-1",
        "assistant-1",
        "tool-1",
        "assistant-1-segment-1",
    ])
    guard history.items.count == 5 else {
        return
    }

    guard case .threadStart(_, let startedAt) = history.items[0] else {
        Issue.record("expected thread start"); return
    }
    #expect(startedAt == historyDate(0))

    guard case .message(let user) = history.items[1] else {
        Issue.record("expected user message"); return
    }
    #expect(user.role == .user)
    #expect(user.timestamp == Date(timeIntervalSince1970: 1_787_601_603))

    guard case .message(let assistant) = history.items[2] else {
        Issue.record("expected assistant message"); return
    }
    #expect(assistant.role == .assistant)
    #expect(assistant.attribution.model == "gpt-5.6-sol")
    #expect(assistant.attribution.provider == "openai-codex")
    #expect(assistant.attribution.mode == "plan")
    #expect(assistant.visibleText == "I will update it.")
    #expect(assistant.showsResponseMetadata)

    guard case .tool(let tool) = history.items[3] else {
        Issue.record("expected paired tool"); return
    }
    #expect(tool.id == "tool-1")
    #expect(tool.arguments["path"]?.stringValue == "/tmp/project/App.swift")
    #expect(tool.phase == .complete)
    #expect(history.items.filter { if case .tool = $0 { true } else { false } }.count == 1)

    guard case .message(let continuation) = history.items[4] else {
        Issue.record("expected assistant continuation"); return
    }
    #expect(continuation.visibleText == "The update is complete.")
    #expect(!continuation.showsResponseMetadata)
}

@Test func historyMapperAnnotatesChangesAfterConversationStarts() throws {
    let header = SessionHeader(
        id: "session-2",
        cwd: "/tmp/project",
        timestamp: "2026-08-24T20:00:00.000Z",
        version: 3,
        title: nil,
        titleSource: nil,
        parentSession: nil)
    let entries: [SessionEntry] = [
        .modelChange(
            base: historyBase("model-1", nil, 1),
            selection: SessionModelSelection(
                model: "anthropic/claude-opus-4-8",
                role: nil,
                resolvedModelIsFallback: false)),
        .message(
            base: historyBase("user-1", "model-1", 2),
            message: try historyJSON(#"{"role":"user","content":"Start","timestamp":1787601602000}"#)),
        .modelChange(
            base: historyBase("model-2", "user-1", 3),
            selection: SessionModelSelection(
                model: "openai-codex/gpt-5.6-sol",
                role: "temporary",
                resolvedModelIsFallback: true)),
        .thinkingLevelChange(
            base: historyBase("thinking-1", "model-2", 4),
            selection: SessionThinkingSelection(effective: "high", configured: "auto")),
        .modeChange(
            base: historyBase("mode-1", "thinking-1", 5),
            selection: SessionModeSelection(mode: "design", data: nil)),
        .compaction(
            base: historyBase("compact-1", "mode-1", 6),
            value: SessionCompaction(
                summary: "Earlier transcript",
                shortSummary: "Earlier work",
                firstKeptEntryId: "user-1",
                tokensBefore: 12_000,
                tokensAfter: 2_400,
                method: "snapcompact",
                warning: nil)),
    ]

    let history = TranscriptHistoryMapper.map(header: header, path: entries)
    let annotations = history.items.compactMap { item -> TranscriptAnnotation? in
        guard case .annotation(let annotation) = item else { return nil }
        return annotation
    }

    #expect(annotations.map(\.kind) == [.model, .thinking, .mode, .compaction])
    #expect(annotations[0].title == "Model changed to GPT-5.6 Sol")
    #expect(annotations[0].detail == "Temporary fallback")
    #expect(annotations[1].title == "Thinking set to High")
    #expect(annotations[1].detail == "Auto")
    #expect(annotations[2].title == "Design mode")
    #expect(annotations[3].detail == "12,000 → 2,400 tokens")
}

@Test func historyMapperRestoresPerAgentTaskResults() throws {
    let header = SessionHeader(
        id: "session-agents",
        cwd: "/tmp/project",
        timestamp: "2026-08-24T20:00:00.000Z",
        version: 3,
        title: nil,
        titleSource: nil,
        parentSession: nil)
    let entries: [SessionEntry] = [
        .message(
            base: historyBase("assistant-task", nil, 1),
            message: try historyJSON(#"{"role":"assistant","content":[{"type":"toolCall","id":"task-1","name":"task","arguments":{"task":"Fan out"}}]}"#)),
        .message(
            base: historyBase("task-result", "assistant-task", 2),
            message: try historyJSON(#"{"role":"toolResult","toolCallId":"task-1","toolName":"task","isError":false,"details":{"results":[{"index":0,"id":"agent-a","agent":"worker","task":"Build","output":"Built.","exitCode":0},{"index":1,"id":"agent-b","agent":"reviewer","task":"Review","output":"Approved.","exitCode":0}]}}"#)),
    ]

    let history = TranscriptHistoryMapper.map(header: header, path: entries)
    let agents = history.items.compactMap { item -> SubagentPresentation? in
        guard case .subagent(let presentation) = item else { return nil }
        return presentation
    }

    #expect(agents.map(\.id) == ["agent-a", "agent-b"])
    #expect(agents.map(\.resultText) == ["Built.", "Approved."])
}

@Test func historyMapperKeepsEmptyTerminalFailuresVisible() throws {
    let header = SessionHeader(
        id: "session-failures",
        cwd: "/tmp/project",
        timestamp: "2026-08-24T20:00:00.000Z",
        version: 3,
        title: nil,
        titleSource: nil,
        parentSession: nil)
    let entries: [SessionEntry] = [
        .message(
            base: historyBase("error", nil, 1),
            message: try historyJSON(#"{"role":"assistant","content":[],"stopReason":"error","errorMessage":"Provider unavailable"}"#)),
        .message(
            base: historyBase("aborted", "error", 2),
            message: try historyJSON(#"{"role":"assistant","content":[],"stopReason":"aborted"}"#)),
    ]

    let messages: [TranscriptMessage] = TranscriptHistoryMapper.map(
        header: header,
        path: entries).items.compactMap {
        guard case .message(let message) = $0 else { return nil }
        return message
    }

    #expect(messages.map(\.visibleText) == ["Provider unavailable", "Response aborted."])
}

private func historyBase(_ id: String, _ parentID: String?, _ second: Int) -> SessionEntryBase {
    SessionEntryBase(
        id: id,
        parentId: parentID,
        timestamp: String(format: "2026-08-24T20:00:%02d.000Z", second))
}

private func historyDate(_ second: Int) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(
        from: String(format: "2026-08-24T20:00:%02d.000Z", second))!
}

private func historyJSON(_ source: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(source.utf8))
}
