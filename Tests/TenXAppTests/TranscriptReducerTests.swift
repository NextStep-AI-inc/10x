import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Test func messageUpdatesReplaceTheInflightSnapshot() throws {
    var reducer = TranscriptReducer()

    reducer.consume(try eventFrame("""
        {"type":"message_start","message":{"id":"m1","role":"assistant","content":[]}}
        """))
    reducer.consume(try eventFrame("""
        {"type":"message_update","message":{"id":"m1","role":"assistant","content":[{"type":"text","text":"Complete snapshot"}]},"assistantMessageEvent":{"type":"text_delta","delta":"snapshot"}}
        """))

    #expect(reducer.items.count == 1)
    guard case .message(let message) = reducer.items[0] else {
        Issue.record("Expected one message item")
        return
    }
    #expect(message.id == "m1")
    #expect(message.raw["content"]?.arrayValue?.first?["text"]?.stringValue == "Complete snapshot")
    #expect(!message.isFinal)
}

@Test func messageEndReplacesAndFinalizesTheInflightSnapshot() throws {
    var reducer = TranscriptReducer()

    reducer.consume(try eventFrame("""
        {"type":"message_start","message":{"id":"m1","role":"assistant","content":[]}}
        """))
    reducer.consume(try eventFrame("""
        {"type":"message_end","message":{"id":"m1","role":"assistant","content":[{"type":"text","text":"Final text"}],"stopReason":"stop"}}
        """))

    #expect(reducer.items.count == 1)
    guard case .message(let message) = reducer.items[0] else {
        Issue.record("Expected one message item")
        return
    }
    #expect(message.raw["content"]?.arrayValue?.first?["text"]?.stringValue == "Final text")
    #expect(message.isFinal)
}

@Test func explicitNonterminalAgentEndKeepsTheSessionStreaming() throws {
    var reducer = TranscriptReducer()
    reducer.runtimeState = .streaming

    reducer.consume(try eventFrame("""
        {"type":"agent_end","messages":[],"isTerminal":false}
        """))

    #expect(reducer.runtimeState == .streaming)
}

@Test func absentOrTrueTerminalFlagSettlesTheSession() throws {
    var reducer = TranscriptReducer()
    reducer.runtimeState = .streaming

    reducer.consume(try eventFrame("""
        {"type":"agent_end","messages":[]}
        """))
    #expect(reducer.runtimeState == .idle)

    reducer.runtimeState = .streaming
    reducer.consume(try eventFrame("""
        {"type":"agent_end","messages":[],"isTerminal":true}
        """))
    #expect(reducer.runtimeState == .idle)
}

@Test func pairedToolResultMessageDoesNotDuplicateTheToolCard() throws {
    var reducer = TranscriptReducer()

    reducer.consume(try eventFrame("""
        {"type":"tool_execution_start","toolCallId":"t1","toolName":"bash","args":{"command":"pwd"}}
        """))
    reducer.consume(try eventFrame("""
        {"type":"tool_execution_end","toolCallId":"t1","toolName":"bash","result":{"content":[{"type":"text","text":"/tmp"}]},"isError":false}
        """))
    reducer.consume(try eventFrame("""
        {"type":"message_start","message":{"role":"toolResult","toolCallId":"t1","toolName":"bash","content":[{"type":"text","text":"/tmp"}],"isError":false}}
        """))
    reducer.consume(try eventFrame("""
        {"type":"message_end","message":{"role":"toolResult","toolCallId":"t1","toolName":"bash","content":[{"type":"text","text":"/tmp"}],"isError":false}}
        """))

    #expect(reducer.items.count == 1)
    guard case .tool(let presentation) = reducer.items[0] else {
        Issue.record("Expected one tool card")
        return
    }
    #expect(presentation.name == "bash")
}

@Test func promptResultSettlesACommandOnlyTurn() throws {
    var reducer = TranscriptReducer()
    reducer.runtimeState = .streaming

    reducer.consume(try eventFrame("""
        {"type":"prompt_result","agentInvoked":false}
        """))

    #expect(reducer.runtimeState == .idle)
}

@Test func historicalToolCallsKeepArgumentsAndMergeTheirResults() throws {
    var reducer = TranscriptReducer()
    reducer.load(messages: [
        try message("""
            {"role":"assistant","content":[{"type":"toolCall","id":"t1","name":"bash","arguments":{"command":"pwd"}}]}
            """),
        try message("""
            {"role":"toolResult","toolCallId":"t1","toolName":"bash","content":[{"type":"text","text":"/tmp"}],"isError":false}
            """),
    ])

    #expect(reducer.items.count == 1)
    guard case .tool(let tool) = reducer.items[0] else {
        Issue.record("Expected one historical tool card")
        return
    }
    #expect(tool.arguments["command"]?.stringValue == "pwd")
    #expect(tool.result?["content"]?.arrayValue?.first?["text"]?.stringValue == "/tmp")
}

@Test func liveMessagesKeepTheirOwnTimestampAndModel() throws {
    var reducer = TranscriptReducer()
    reducer.consume(try eventFrame("""
        {"type":"message_start","message":{"id":"m1","role":"assistant","provider":"anthropic","model":"claude-opus-4-8","timestamp":1787601604000,"content":[{"type":"text","text":"Answer"}]}}
        """))

    guard case .message(let message) = reducer.items[0] else {
        Issue.record("Expected a message"); return
    }
    #expect(message.timestamp == Date(timeIntervalSince1970: 1_787_601_604))
    #expect(message.attribution.provider == "anthropic")
    #expect(message.attribution.model == "claude-opus-4-8")
}

@Test func lifecycleEventsBecomeUsefulAnnotations() throws {
    var reducer = TranscriptReducer()
    reducer.consume(try eventFrame("""
        {"type":"auto_retry_start","attempt":2,"maxAttempts":4,"delayMs":1500,"errorMessage":"Rate limited"}
        """))
    reducer.consume(try eventFrame("""
        {"type":"retry_fallback_applied","from":"anthropic/claude-opus-4-8","to":"openai-codex/gpt-5.6-sol","role":"default"}
        """))
    reducer.consume(try eventFrame("""
        {"type":"thinking_level_changed","thinkingLevel":"high","configured":"auto"}
        """))
    reducer.consume(try eventFrame("""
        {"type":"auto_compaction_end","action":"snapcompact","aborted":false,"willRetry":false,"result":{"tokensBefore":12000,"tokensAfter":2400}}
        """))

    let annotations = reducer.items.compactMap { item -> TranscriptAnnotation? in
        guard case .annotation(let annotation) = item else { return nil }
        return annotation
    }
    #expect(annotations.map(\.kind) == [.retry, .model, .thinking, .compaction])
    #expect(annotations[0].title == "Retrying response")
    #expect(annotations[0].detail == "Attempt 2 of 4 · 1.5s")
    #expect(annotations[1].title == "Fallback to GPT-5.6 Sol")
    #expect(annotations[2].title == "Thinking set to High")
    #expect(annotations[3].title == "Context compacted")
}

@Test func persistedReconciliationReplacesTranscriptWithoutDuplicatingLiveItems() throws {
    var reducer = TranscriptReducer()
    reducer.consume(try eventFrame("""
        {"type":"message_end","message":{"id":"live","role":"assistant","content":[{"type":"text","text":"Persisted"}]}}
        """))
    reducer.consume(try eventFrame("""
        {"type":"tool_execution_start","toolCallId":"running","toolName":"bash","args":{"command":"sleep 1"}}
        """))
    reducer.appendNotice(level: "warning", message: "Keep this notice")

    let persistedMessage = TranscriptMessage(
        id: "entry-1",
        raw: try message("""
            {"role":"assistant","content":[{"type":"text","text":"Persisted"}]}
            """),
        isFinal: true)
    let history = TranscriptHistory(items: [
        .threadStart(id: "thread", date: .distantPast),
        .message(persistedMessage),
    ])

    reducer.reconcile(history: history)

    #expect(reducer.items.filter { if case .message = $0 { true } else { false } }.count == 1)
    #expect(reducer.items.contains { $0.id == "running" })
    #expect(reducer.items.contains { if case .notice = $0 { true } else { false } })
}

@Test func fallbackHistoryCreatesOnlyOneThreadStart() {
    var reducer = TranscriptReducer()
    let started = Date(timeIntervalSince1970: 1_787_601_600)

    reducer.ensureThreadStart(date: started)
    reducer.ensureThreadStart(date: .distantFuture)

    let starts = reducer.items.compactMap { item -> Date? in
        guard case .threadStart(_, let date) = item else { return nil }
        return date
    }
    #expect(starts.count == 1)
    #expect(starts[0] == started)
}

@Test func reconciliationWarningCoalescesAndClears() {
    var reducer = TranscriptReducer()
    reducer.setReconciliationWarning(isPresented: true)
    reducer.setReconciliationWarning(isPresented: true)
    #expect(reducer.items.filter { $0.id == "reconciliation-warning" }.count == 1)

    reducer.setReconciliationWarning(isPresented: false)
    #expect(!reducer.items.contains { $0.id == "reconciliation-warning" })
}

@Test func transcriptFollowsOnlyWhenViewportIsNearBottom() {
    #expect(TranscriptView.shouldFollowBottom(
        contentOffset: 700,
        containerHeight: 300,
        contentHeight: 1_050))
    #expect(!TranscriptView.shouldFollowBottom(
        contentOffset: 200,
        containerHeight: 300,
        contentHeight: 1_050))
}

private func eventFrame(_ json: String) throws -> RpcFrame {
    try RpcFrame.decode(line: Data(json.utf8))
}

private func message(_ json: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
}
