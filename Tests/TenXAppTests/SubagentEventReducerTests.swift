import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Test func subagentLifecycleAndProgressUpdateOneStablePresentation() throws {
    var reducer = SubagentEventReducer()
    reducer.consume(type: "subagent_lifecycle", payload: try value("""
        {"payload":{"id":"agent-1","agent":"explorer","description":"Map the session flow","status":"started","sessionFile":"/tmp/agent.jsonl","parentToolCallId":"task-1","index":0}}
        """))
    reducer.consume(type: "subagent_progress", payload: try value("""
        {"payload":{"index":0,"agent":"explorer","task":"Map the session flow","parentToolCallId":"task-1","sessionFile":"/tmp/agent.jsonl","progress":{"id":"agent-1","status":"running","durationMs":1200,"resolvedModel":"anthropic/claude-sonnet-4-6:high","modelRole":"fast","toolCount":4,"tokens":920,"requests":2,"cost":0.014,"currentTool":"read","recentOutput":["Mapped controller","Found event boundary"]}}}
        """))

    #expect(reducer.presentations.count == 1)
    let presentation = try #require(reducer.presentations.first)
    #expect(presentation.id == "agent-1")
    #expect(presentation.agent == "explorer")
    #expect(presentation.actualModel == "claude-sonnet-4-6")
    #expect(presentation.thinkingLevel == "high")
    #expect(presentation.modelRole == "fast")
    #expect(presentation.parentToolCallID == "task-1")
    #expect(presentation.sessionFile == "/tmp/agent.jsonl")
    #expect(presentation.status == .running)
    #expect(presentation.recentOutput == ["Mapped controller", "Found event boundary"])
}

@Test func subagentProgressIsBoundedAndIgnoresOlderSnapshots() throws {
    var reducer = SubagentEventReducer()
    reducer.consume(type: "subagent_progress", payload: try value("""
        {"payload":{"index":1,"agent":"worker","task":"Implement UI","progress":{"id":"agent-2","status":"running","durationMs":2000,"toolCount":5,"recentTools":[{"tool":"read","endMs":1},{"tool":"grep","endMs":2},{"tool":"edit","endMs":3},{"tool":"bash","endMs":4},{"tool":"write","endMs":5}],"recentOutput":["one","two","three","four","five"]}}}
        """))
    reducer.consume(type: "subagent_progress", payload: try value("""
        {"payload":{"index":1,"agent":"worker","task":"Implement UI","progress":{"id":"agent-2","status":"running","durationMs":1000,"toolCount":1,"recentOutput":["stale"]}}}
        """))

    let presentation = try #require(reducer.presentations.first)
    #expect(presentation.durationMilliseconds == 2000)
    #expect(presentation.toolCount == 5)
    #expect(presentation.recentTools.map(\.name) == ["edit", "bash", "write"])
    #expect(presentation.recentOutput == ["three", "four", "five"])
}

@Test func subagentCompletionKeepsProgressAndAttachesParentResult() throws {
    var reducer = SubagentEventReducer()
    reducer.consume(type: "subagent_progress", payload: try value("""
        {"payload":{"index":2,"agent":"reviewer","task":"Review implementation","parentToolCallId":"task-3","progress":{"id":"agent-3","status":"running","durationMs":800,"resolvedModel":"openai-codex/gpt-5.6-sol","recentOutput":["Reviewing"]}}}
        """))
    reducer.consume(type: "subagent_lifecycle", payload: try value("""
        {"payload":{"id":"agent-3","agent":"reviewer","description":"Review implementation","status":"completed","parentToolCallId":"task-3","index":2}}
        """))
    reducer.attachResult(
        parentToolCallID: "task-3",
        result: try value(#"{"content":[{"type":"text","text":"No blocking findings."}]}"#))

    let presentation = try #require(reducer.presentations.first)
    #expect(presentation.status == .completed)
    #expect(presentation.actualModel == "gpt-5.6-sol")
    #expect(presentation.recentOutput == ["Reviewing"])
    #expect(presentation.resultText == "No blocking findings.")
}

@Test func transcriptReducerCoalescesSubagentFramesAndAssociatesTaskResult() throws {
    var reducer = TranscriptReducer()
    reducer.consume(try event("""
        {"type":"subagent_lifecycle","payload":{"id":"agent-4","agent":"worker","description":"Build cards","status":"started","parentToolCallId":"task-4","index":0}}
        """))
    reducer.consume(try event("""
        {"type":"subagent_progress","payload":{"index":0,"agent":"worker","task":"Build cards","parentToolCallId":"task-4","progress":{"id":"agent-4","status":"running","durationMs":400,"resolvedModel":"openai-codex/gpt-5.6-terra"}}}
        """))
    reducer.consume(try event("""
        {"type":"tool_execution_end","toolCallId":"task-4","toolName":"task","result":{"content":[{"type":"text","text":"Cards built."}]},"isError":false}
        """))

    let subagents = reducer.items.compactMap { item -> SubagentPresentation? in
        guard case .subagent(let presentation) = item else { return nil }
        return presentation
    }
    #expect(subagents.count == 1)
    #expect(subagents[0].actualModel == "gpt-5.6-terra")
    #expect(subagents[0].resultText == "Cards built.")
}

private func value(_ json: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
}

private func event(_ json: String) throws -> RpcFrame {
    try RpcFrame.decode(line: Data(json.utf8))
}
