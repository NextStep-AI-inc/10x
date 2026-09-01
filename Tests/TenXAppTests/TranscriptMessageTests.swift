import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Test func normalizerPreservesTextToolTextOrder() throws {
    let raw = try decodeJSON(#"""
    {
      "role": "assistant",
      "provider": "openai-codex",
      "model": "gpt-5.6-sol",
      "content": [
        {"type": "text", "text": "I will inspect this."},
        {"type": "image", "data": "AQ==", "mimeType": "image/png"},
        {"type": "toolCall", "id": "read-1", "name": "read", "arguments": {"path": "App.swift"}},
        {"type": "analysis", "text": "Private reasoning"},
        {"type": "text", "text": "The issue is in the reducer."}
      ]
    }
    """#)

    let items = TranscriptMessageNormalizer.items(
        id: "assistant-1",
        raw: raw,
        isFinal: false)

    #expect(items.map(\.id) == ["assistant-1", "read-1", "assistant-1-segment-1"])
    #expect(items.compactMap(message(from:)).map(\.visibleText) == [
        "I will inspect this.",
        "The issue is in the reducer.",
    ])
    #expect(items.compactMap(message(from:)).map(\.showsResponseMetadata) == [true, false])
    #expect(items.compactMap(message(from:)).first?.document.images.count == 1)
}

@Test func normalizerReusesInlineToolExecutionState() throws {
    let completed = ToolPresentation(
        id: "bash-1",
        name: "bash",
        arguments: .object(["command": .string("pwd")]),
        result: .object(["output": .string("/tmp")]),
        phase: .complete,
        startDate: Date(timeIntervalSince1970: 10),
        endDate: Date(timeIntervalSince1970: 11))
    let raw = try decodeJSON(#"""
    {"role":"assistant","content":[{"type":"toolCall","id":"bash-1","name":"bash","arguments":{"command":"pwd"}}]}
    """#)

    let items = TranscriptMessageNormalizer.items(
        id: "assistant-1",
        raw: raw,
        isFinal: true,
        existingTools: [completed.id: completed])

    #expect(items == [.tool(completed)])
}

@Test func normalizerEmitsOnlyTheFirstDuplicateToolCallID() throws {
    let raw = try decodeJSON(#"""
    {"role":"assistant","content":[
      {"type":"text","text":"Before"},
      {"type":"toolCall","id":"read-1","name":"read","arguments":{"path":"App.swift"}},
      {"type":"toolCall","id":"read-1","name":"read","arguments":{"path":"App.swift"}},
      {"type":"text","text":"After"}
    ]}
    """#)

    let items = TranscriptMessageNormalizer.items(
        id: "assistant-1",
        raw: raw,
        isFinal: false)

    #expect(items.map(\.id) == ["assistant-1", "read-1", "assistant-1-segment-1"])
    #expect(items.filter { if case .tool = $0 { return true }; return false }.count == 1)
    #expect(Set(items.map(\.id)).count == items.count)
}

@Test func malformedToolCallDoesNotCreateAGroupBoundary() throws {
    let raw = try decodeJSON(#"""
    {"role":"assistant","content":[
      {"type":"text","text":"Before"},
      {"type":"toolCall","name":"read"},
      {"type":"text","text":"After"}
    ]}
    """#)

    let items = TranscriptMessageNormalizer.items(
        id: "assistant-1",
        raw: raw,
        isFinal: false)

    #expect(items.count == 1)
    #expect(items.compactMap(message(from:)).map(\.visibleText) == ["Before\nAfter"])
    #expect(items.allSatisfy { if case .tool = $0 { return false }; return true })
}

@Test func nonArrayEmptyInflightAssistantKeepsPlaceholder() throws {
    let raw = try decodeJSON(#"{"role":"assistant","content":""}"#)

    let items = TranscriptMessageNormalizer.items(
        id: "assistant-1",
        raw: raw,
        isFinal: false)

    #expect(items.count == 1)
    guard let message = items.compactMap(message(from:)).first else {
        Issue.record("An empty in-flight assistant message should be retained")
        return
    }
    #expect(message.id == "assistant-1")
    #expect(message.isFinal == false)
    #expect(message.showsResponseMetadata == true)
}

@Test func terminalFailureAroundToolEmitsOneFailureMessage() throws {
    let raw = try decodeJSON(#"""
    {"role":"assistant","stopReason":"error","content":[
      {"type":"analysis","text":"Private before"},
      {"type":"toolCall","id":"read-1","name":"read","arguments":{"path":"App.swift"}},
      {"type":"analysis","text":"Private after"}
    ]}
    """#)

    let items = TranscriptMessageNormalizer.items(
        id: "assistant-1",
        raw: raw,
        isFinal: true)

    #expect(items.filter { if case .tool = $0 { return true }; return false }.count == 1)
    let messages = items.compactMap(message(from:))
    #expect(messages.count == 1)
    #expect(messages.first?.visibleText == "Response failed.")
    #expect(messages.first?.showsResponseMetadata == true)
}

@Test func normalizerRefreshesExistingToolDetailsFromAuthoritativeBlock() throws {
    let started = Date(timeIntervalSince1970: 10)
    let ended = Date(timeIntervalSince1970: 11)
    let result = JSONValue.object(["output": .string("done")])
    let existing = ToolPresentation(
        id: "bash-1",
        name: "stale-bash",
        arguments: .object(["command": .string("old")]),
        result: result,
        phase: .complete,
        startDate: started,
        endDate: ended)
    let raw = try decodeJSON(#"""
    {"role":"assistant","content":[{"type":"toolCall","id":"bash-1","name":"bash","arguments":{"command":"pwd"}}]}
    """#)

    let items = TranscriptMessageNormalizer.items(
        id: "assistant-1",
        raw: raw,
        isFinal: true,
        existingTools: [existing.id: existing])

    guard case .tool(let tool) = items.first else {
        Issue.record("The assistant tool call should produce a tool row")
        return
    }
    #expect(tool.name == "bash")
    #expect(tool.arguments == .object(["command": .string("pwd")]))
    #expect(tool.phase == existing.phase)
    #expect(tool.result == existing.result)
    #expect(tool.startDate == existing.startDate)
    #expect(tool.endDate == existing.endDate)
}

private func decodeJSON(_ source: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(source.utf8))
}

private func message(from item: TranscriptItem) -> TranscriptMessage? {
    guard case .message(let message) = item else { return nil }
    return message
}
