import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Test func unknownEventsAreDiscardedWithoutMutation() throws {
    var reducer = TranscriptReducer()

    let nonEvent = try RpcFrame.decode(line: Data(#"{"type":"response","id":"1","command":"get_state","success":true,"data":{}}"#.utf8))
    #expect(reducer.consume(nonEvent) == .none)
    #expect(reducer.consume(try eventFrame("""
        {"type":"unknown_future_event","payload":{"large":"ignored"}}
        """)) == .none)

    #expect(reducer.items.isEmpty)
}

@Test func tenThousandUnknownEventsAddNoRows() throws {
    var reducer = TranscriptReducer()
    let frame = try eventFrame("""
        {"type":"unsupported_progress","index":1,"payload":{"text":"ignored"}}
        """)

    for _ in 0..<10_000 {
        #expect(reducer.consume(frame) == .none)
    }

    #expect(reducer.items.isEmpty)
}

@Test func malformedKnownEventsDoNotPublish() throws {
    var reducer = TranscriptReducer()

    #expect(reducer.consume(try eventFrame("""
        {"type":"message_start"}
        """)) == .none)
    #expect(reducer.consume(try eventFrame("""
        {"type":"message_update"}
        """)) == .none)
    #expect(reducer.consume(try eventFrame("""
        {"type":"message_end"}
        """)) == .none)
    #expect(reducer.consume(try eventFrame("""
        {"type":"message_start","message":{"role":"toolResult","toolName":"bash","content":[{"type":"text","text":"missing id"}],"isError":false}}
        """)) == .none)
    #expect(reducer.consume(try eventFrame("""
        {"type":"message_end","message":{"role":"toolResult","toolName":"bash","content":[{"type":"text","text":"missing id"}],"isError":false}}
        """)) == .none)
    #expect(reducer.consume(try eventFrame("""
        {"type":"tool_execution_update","toolName":"bash"}
        """)) == .none)
    #expect(reducer.consume(try eventFrame("""
        {"type":"subagent_progress","payload":{"id":"missing"}}
        """)) == .none)
    #expect(reducer.consume(try eventFrame("""
        {"type":"subagent_progress","payload":{"progress":{"durationMs":10,"description":"orphan"}}}
        """)) == .none)
    #expect(reducer.consume(try eventFrame("""
        {"type":"subagent_progress","payload":{"index":0,"progress":{"durationMs":11,"description":"still orphaned"}}}
        """)) == .none)

    #expect(reducer.items.isEmpty)
    #expect(reducer.runtimeState == .idle)
}

@Test func messageAndToolUpdatesAreCoalesced() throws {
    var reducer = TranscriptReducer()

    #expect(reducer.consume(try eventFrame("""
        {"type":"message_update","message":{"id":"m1","role":"assistant","content":[{"type":"text","text":"Draft"}]}}
        """)) == .coalesced)
    #expect(reducer.consume(try eventFrame("""
        {"type":"message_update","message":{"id":"m1","role":"assistant","content":[{"type":"text","text":"Draft"}]}}
        """)) == .none)
    #expect(reducer.consume(try eventFrame("""
        {"type":"message_update","message":{"id":"m1","role":"assistant","content":[{"type":"text","text":"Draft plus"}]}}
        """)) == .coalesced)

    #expect(reducer.consume(try eventFrame("""
        {"type":"tool_execution_start","toolCallId":"t1","toolName":"bash","args":{"command":"sleep 1"}}
        """)) == .immediate)
    #expect(reducer.consume(try eventFrame("""
        {"type":"tool_execution_update","toolCallId":"t1","toolName":"bash","partialResult":{"content":[{"type":"text","text":"running"}]}}
        """)) == .coalesced)
    #expect(reducer.consume(try eventFrame("""
        {"type":"tool_execution_update","toolCallId":"t1","toolName":"bash","partialResult":{"content":[{"type":"text","text":"running"}]}}
        """)) == .none)

    #expect(reducer.consume(try eventFrame("""
        {"type":"subagent_lifecycle","payload":{"id":"s1","index":1,"label":"Analyze","status":"running"}}
        """)) == .immediate)
    #expect(reducer.consume(try eventFrame("""
        {"type":"subagent_progress","payload":{"progress":{"id":"s1","durationMs":10,"description":"halfway"}}}
        """)) == .coalesced)
    #expect(reducer.consume(try eventFrame("""
        {"type":"subagent_progress","payload":{"progress":{"id":"s1","durationMs":10,"description":"halfway"}}}
        """)) == .none)
}

@Test func boundariesAndVisibleChangesAreImmediate() throws {
    var reducer = TranscriptReducer()

    #expect(reducer.load(messages: [try message("""
        {"role":"user","content":[{"type":"text","text":"Hi"}]}
        """)]) == .immediate)
    #expect(reducer.load(messages: [try message("""
        {"role":"user","content":[{"type":"text","text":"Hi"}]}
        """)]) == .none)

    let history = TranscriptHistory(items: [
        .threadStart(id: "thread", date: Date(timeIntervalSince1970: 1))
    ])
    #expect(reducer.load(history: history) == .immediate)
    #expect(reducer.load(history: history) == .none)
    #expect(reducer.ensureThreadStart(date: .distantFuture) == .none)
    #expect(reducer.setReconciliationWarning(isPresented: true) == .immediate)
    #expect(reducer.setReconciliationWarning(isPresented: true) == .none)
    #expect(reducer.setReconciliationWarning(isPresented: false) == .immediate)
    #expect(reducer.setReconciliationWarning(isPresented: false) == .none)
    #expect(reducer.appendNotice(level: "info", message: "Visible") == .immediate)

    let extensionState = ExtensionUIState.confirm(
        id: "ext-1",
        title: "Approve",
        message: "Continue?",
        timeout: nil)
    #expect(reducer.upsertExtensionUI(extensionState) == .immediate)
    #expect(reducer.upsertExtensionUI(extensionState) == .none)
    #expect(reducer.removeExtensionUI(id: extensionState.id) == .immediate)
    #expect(reducer.removeExtensionUI(id: extensionState.id) == .none)

    #expect(reducer.consume(try eventFrame("""
        {"type":"agent_start"}
        """)) == .immediate)
    #expect(reducer.consume(try eventFrame("""
        {"type":"message_start","message":{"id":"m1","role":"assistant","content":[]}}
        """)) == .immediate)
    #expect(reducer.consume(try eventFrame("""
        {"type":"message_end","message":{"id":"m1","role":"assistant","content":[{"type":"text","text":"Done"}]}}
        """)) == .immediate)
    #expect(reducer.consume(try eventFrame("""
        {"type":"tool_execution_end","toolCallId":"t1","toolName":"bash","result":{"content":[{"type":"text","text":"done"}]},"isError":false}
        """)) == .immediate)
    #expect(reducer.consume(try eventFrame("""
        {"type":"subagent_lifecycle","payload":{"id":"s2","index":2,"label":"Review","status":"completed"}}
        """)) == .immediate)
    #expect(reducer.consume(try eventFrame("""
        {"type":"notice","level":"info","message":"Heads up"}
        """)) == .immediate)
    #expect(reducer.consume(try eventFrame("""
        {"type":"thinking_level_changed","thinkingLevel":"high","configured":"auto"}
        """)) == .immediate)
    #expect(reducer.consume(try eventFrame("""
        {"type":"agent_end","isTerminal":true}
        """)) == .immediate)

    let reconciledHistory = TranscriptHistory(items: [
        .threadStart(id: "thread", date: Date(timeIntervalSince1970: 1)),
        .message(TranscriptMessage(
            id: "persisted-message",
            raw: try message("""
                {"role":"assistant","content":[{"type":"text","text":"Persisted"}]}
                """),
            isFinal: true))
    ])
    #expect(reducer.reconcile(history: reconciledHistory) == .immediate)
    #expect(reducer.reconcile(history: reconciledHistory) == .none)
}

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

@Test func liveAssistantToolSegmentsStayInSourceOrderAndUpdateInPlace() throws {
    var reducer = TranscriptReducer()
    let assistant = """
        {"id":"assistant-1","role":"assistant","content":[{"type":"text","text":"Checking."},{"type":"toolCall","id":"read-1","name":"read","arguments":{"path":"/tmp/project/App.swift"}},{"type":"text","text":"Found it."}]}
        """

    _ = reducer.consume(try eventFrame("""
        {"type":"message_update","message":\(assistant)}
        """))

    #expect(reducer.items.map(\.id) == ["assistant-1", "read-1", "assistant-1-segment-1"])
    let messages = reducer.items.compactMap { item -> TranscriptMessage? in
        guard case .message(let message) = item else { return nil }
        return message
    }
    #expect(messages.map(\.visibleText) == ["Checking.", "Found it."])

    _ = reducer.consume(try eventFrame("""
        {"type":"message_update","message":{"id":"assistant-1","role":"assistant","content":[{"type":"text","text":"Checking again."},{"type":"toolCall","id":"read-1","name":"read","arguments":{"path":"/tmp/project/App.swift","lineEnd":12}},{"type":"text","text":"Found the updated file."}]}}
        """))
    #expect(reducer.items.map(\.id) == ["assistant-1", "read-1", "assistant-1-segment-1"])

    _ = reducer.consume(try eventFrame("""
        {"type":"tool_execution_end","toolCallId":"read-1","toolName":"read","result":{"content":[{"type":"text","text":"file contents"}]},"isError":false}
        """))

    #expect(reducer.items.map(\.id) == ["assistant-1", "read-1", "assistant-1-segment-1"])
    let tools = reducer.items.compactMap { item -> ToolPresentation? in
        guard case .tool(let tool) = item else { return nil }
        return tool
    }
    #expect(tools.count == 1)
    #expect(tools[0].phase == .complete)
    #expect(tools[0].result != nil)
}

@Test func reconciliationKeepsPendingInlineToolBetweenAssistantSegments() throws {
    var reducer = TranscriptReducer()
    let assistant = """
        {"id":"assistant-1","role":"assistant","content":[{"type":"text","text":"Checking."},{"type":"toolCall","id":"read-1","name":"read","arguments":{"path":"/tmp/project/App.swift"}},{"type":"text","text":"Found it."}]}
        """

    _ = reducer.consume(try eventFrame("""
        {"type":"message_end","message":\(assistant)}
        """))
    let expectedItems = reducer.items

    _ = reducer.reconcile(history: TranscriptHistory(items: []))

    #expect(reducer.items == expectedItems)
    #expect(reducer.items.map(\.id) == ["assistant-1", "read-1", "assistant-1-segment-1"])
}

@Test func duplicateInlineToolIDsDoNotAppendOrCrashOnFullSnapshotReplacement() throws {
    var reducer = TranscriptReducer()
    let assistant = """
        {"id":"assistant-1","role":"assistant","content":[{"type":"text","text":"Before"},{"type":"toolCall","id":"read-1","name":"read","arguments":{"path":"App.swift"}},{"type":"toolCall","id":"read-1","name":"read","arguments":{"path":"App.swift"}},{"type":"text","text":"After"}]}
        """

    _ = reducer.consume(try eventFrame("""
        {"type":"message_update","message":\(assistant)}
        """))
    _ = reducer.consume(try eventFrame("""
        {"type":"message_update","message":\(assistant)}
        """))

    #expect(reducer.items.map(\.id) == ["assistant-1", "read-1", "assistant-1-segment-1"])
    #expect(reducer.items.filter { if case .tool = $0 { return true }; return false }.count == 1)
    #expect(Set(reducer.items.map(\.id)).count == reducer.items.count)
}

@Test func toolIDCollisionDoesNotReplaceAnExistingMessage() throws {
    var reducer = TranscriptReducer()
    _ = reducer.consume(try eventFrame("""
        {"type":"message_end","message":{"id":"shared","role":"assistant","content":[{"type":"text","text":"Keep this message"}]}}
        """))
    _ = reducer.consume(try eventFrame("""
        {"type":"message_update","message":{"id":"assistant-2","role":"assistant","content":[{"type":"text","text":"Read it"},{"type":"toolCall","id":"shared","name":"read","arguments":{"path":"App.swift"}}]}}
        """))
    _ = reducer.consume(try eventFrame("""
        {"type":"tool_execution_end","toolCallId":"shared","toolName":"read","result":{"content":[{"type":"text","text":"file contents"}]},"isError":false}
        """))

    let sharedMessages = reducer.items.compactMap { item -> TranscriptMessage? in
        guard case .message(let message) = item, message.id == "shared" else { return nil }
        return message
    }
    let sharedTools = reducer.items.compactMap { item -> ToolPresentation? in
        guard case .tool(let tool) = item, tool.id == "shared" else { return nil }
        return tool
    }
    #expect(sharedMessages.map(\.visibleText) == ["Keep this message"])
    #expect(sharedTools.count == 1)
    #expect(sharedTools[0].phase == .complete)

    let sharedItems = reducer.items.filter { $0.id == "shared" }
    #expect(sharedItems.map(\.id) == ["shared", "shared"])
    #expect(Set(sharedItems.map(\.viewID)).count == 2)
}

@Test func toolPersistenceDoesNotResolveAMessageWithTheSameID() throws {
    var reducer = TranscriptReducer()
    _ = reducer.consume(try eventFrame("""
        {"type":"message_end","message":{"id":"shared","role":"assistant","content":[{"type":"text","text":"Keep this message"}]}}
        """))
    _ = reducer.consume(try eventFrame("""
        {"type":"tool_execution_end","toolCallId":"shared","toolName":"read","result":{"content":[{"type":"text","text":"file contents"}]},"isError":false}
        """))

    _ = reducer.reconcile(history: TranscriptHistory(items: [
        .tool(ToolPresentation(
            id: "shared",
            name: "read",
            arguments: .object([:]),
            result: try message("""
                {"role":"toolResult","toolCallId":"shared","content":[{"type":"text","text":"file contents"}]}
                """),
            phase: .complete,
            startDate: .distantPast,
            endDate: .distantPast)),
    ]))

    let sharedMessages = reducer.items.compactMap { item -> TranscriptMessage? in
        guard case .message(let message) = item, message.id == "shared" else { return nil }
        return message
    }
    #expect(sharedMessages.map(\.visibleText) == ["Keep this message"])
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

@Test func duplicateTimestamplessToolResultDoesNotRepublishOrChangeDates() throws {
    var reducer = TranscriptReducer()
    let toolResult = """
        {"type":"message_end","message":{"role":"toolResult","toolCallId":"t1","toolName":"bash","content":[{"type":"text","text":"done"}],"isError":false}}
        """

    #expect(reducer.consume(try eventFrame(toolResult)) == .immediate)
    let originalItems = reducer.items
    guard case .tool(let originalTool) = try #require(originalItems.first) else {
        Issue.record("Expected one tool card")
        return
    }

    #expect(reducer.consume(try eventFrame(toolResult)) == .none)
    #expect(reducer.items == originalItems)
    guard case .tool(let reloadedTool) = try #require(reducer.items.first) else {
        Issue.record("Expected one tool card")
        return
    }
    #expect(reloadedTool.startDate == originalTool.startDate)
    #expect(reloadedTool.endDate == originalTool.endDate)
}

@Test func timestamplessResultForRunningToolKeepsLiveDuration() throws {
    var reducer = TranscriptReducer()
    reducer.load(messages: [
        try message("""
            {"role":"assistant","timestamp":1000,"content":[{"type":"toolCall","id":"t1","name":"bash","arguments":{"command":"sleep 1"}}]}
            """),
    ])
    let toolResult = """
        {"type":"message_end","message":{"role":"toolResult","toolCallId":"t1","toolName":"bash","content":[{"type":"text","text":"done"}],"isError":false}}
        """

    #expect(reducer.consume(try eventFrame(toolResult)) == .immediate)
    let originalItems = reducer.items
    guard case .tool(let completedTool) = try #require(originalItems.first) else {
        Issue.record("Expected one tool card")
        return
    }
    let completedEndDate = try #require(completedTool.endDate)
    #expect(completedEndDate > completedTool.startDate)

    #expect(reducer.consume(try eventFrame(toolResult)) == .none)
    #expect(reducer.items == originalItems)
    guard case .tool(let duplicateTool) = try #require(reducer.items.first) else {
        Issue.record("Expected one tool card")
        return
    }
    #expect(duplicateTool.startDate == completedTool.startDate)
    #expect(duplicateTool.endDate == completedTool.endDate)
}

@Test func duplicateIdenticalTerminalToolEventDoesNotRepublishOrChangeDates() throws {
    var reducer = TranscriptReducer()
    let terminalEvent = """
        {"type":"tool_execution_end","toolCallId":"t1","toolName":"bash","result":{"content":[{"type":"text","text":"done"}]},"isError":false}
        """

    #expect(reducer.consume(try eventFrame(terminalEvent)) == .immediate)
    let originalItems = reducer.items
    guard case .tool(let originalTool) = try #require(originalItems.first) else {
        Issue.record("Expected one tool card")
        return
    }

    Thread.sleep(forTimeInterval: 0.01)
    #expect(reducer.consume(try eventFrame(terminalEvent)) == .none)
    #expect(reducer.items == originalItems)
    guard case .tool(let duplicateTool) = try #require(reducer.items.first) else {
        Issue.record("Expected one tool card")
        return
    }
    #expect(duplicateTool.endDate == originalTool.endDate)
}

@Test func repeatedTimestamplessToolHistoryLoadDoesNotRepublishOrChangeItems() throws {
    var reducer = TranscriptReducer()
    let history = [
        try message("""
            {"role":"assistant","content":[{"type":"toolCall","id":"t1","name":"bash","arguments":{"command":"pwd"}}]}
            """),
        try message("""
            {"role":"toolResult","toolCallId":"t1","toolName":"bash","content":[{"type":"text","text":"/tmp"}],"isError":false}
            """),
    ]

    #expect(reducer.load(messages: history) == .immediate)
    let originalItems = reducer.items

    #expect(reducer.load(messages: history) == .none)
    #expect(reducer.items == originalItems)
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
        id: "live",
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

@Test func staleHistoryKeepsFinalLiveBoundariesUntilTheirContentPersists() throws {
    var reducer = TranscriptReducer()
    reducer.consume(try eventFrame("""
        {"type":"message_end","message":{"role":"assistant","timestamp":1787601604000,"content":[{"type":"text","text":"Just finished"}],"stopReason":"stop"}}
        """))
    reducer.consume(try eventFrame("""
        {"type":"tool_execution_end","toolCallId":"live-tool","toolName":"bash","result":{"content":[{"type":"text","text":"done"}]},"isError":false}
        """))

    reducer.reconcile(history: TranscriptHistory(items: [
        .threadStart(id: "thread", date: .distantPast),
    ]))
    let liveMessageID = try #require(reducer.items.compactMap { item -> String? in
        guard case .message(let message) = item else { return nil }
        return message.id
    }.first)
    #expect(liveMessageID.hasPrefix("message-"))
    #expect(reducer.items.contains { $0.id == "live-tool" })

    let persistedMessage = TranscriptMessage(
        id: "persisted-entry-id",
        raw: try message("""
            {"role":"assistant","timestamp":1787601604000,"content":[{"type":"text","text":"Just finished"}],"stopReason":"stop"}
            """),
        isFinal: true)
    let persistedTool = ToolPresentation(
        id: "live-tool",
        name: "bash",
        arguments: .object([:]),
        result: try message("""
            {"role":"toolResult","toolCallId":"live-tool","content":[{"type":"text","text":"done"}]}
            """),
        phase: .complete,
        startDate: .distantPast,
        endDate: .distantPast)
    reducer.reconcile(history: TranscriptHistory(items: [
        .threadStart(id: "thread", date: .distantPast),
        .message(persistedMessage),
        .tool(persistedTool),
    ]))

    let messages = reducer.items.compactMap { item -> TranscriptMessage? in
        guard case .message(let message) = item else { return nil }
        return message
    }
    #expect(messages.count == 1)
    #expect(messages.first?.id == "persisted-entry-id")
    #expect(!reducer.items.contains { $0.id == liveMessageID })
    #expect(reducer.items.filter { $0.id == "live-tool" }.count == 1)
}

@Test func persistedMarkdownReplacesEquivalentPlainLiveMessage() throws {
    var reducer = TranscriptReducer()
    reducer.consume(try eventFrame("""
        {"type":"message_end","message":{"role":"assistant","timestamp":1787601604000,"content":[{"type":"text","text":"Verification completeRead card rendered"}],"stopReason":"stop"}}
        """))
    #expect(reducer.hasPendingPersistence)

    let persistedMessage = TranscriptMessage(
        id: "persisted-entry-id",
        raw: try message(##"{"role":"assistant","timestamp":1787601604000,"content":[{"type":"text","text":"# Verification complete\n\n- Read card rendered"}],"stopReason":"stop"}"##),
        isFinal: true)

    reducer.reconcile(history: TranscriptHistory(items: [
        .threadStart(id: "thread", date: .distantPast),
        .message(persistedMessage),
    ]))

    let messages = reducer.items.compactMap { item -> TranscriptMessage? in
        guard case .message(let message) = item else { return nil }
        return message
    }
    #expect(messages.map(\.id) == ["persisted-entry-id"])
    #expect(messages.first?.visibleText == "# Verification complete\n\n- Read card rendered")
    #expect(!reducer.hasPendingPersistence)
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

@Test func steeringMessagesOmpHidesNeverReachTheTranscript() {
    var reducer = TranscriptReducer()
    let hidden = JSONValue.object([
        "role": .string("custom"),
        "customType": .string("prewalk-plan"),
        "display": .bool(false),
        "content": .string("STOP: In NEXT reply, before further exploration, write a plan."),
    ])

    #expect(reducer.consume(.event(type: "message_start", payload: .object(["message": hidden]))) == .none)
    #expect(reducer.consume(.event(type: "message_end", payload: .object(["message": hidden]))) == .none)
    #expect(reducer.items.isEmpty)
}

@Test func aCustomMessageThatAsksToBeShownIsShown() {
    var reducer = TranscriptReducer()
    let shown = JSONValue.object([
        "role": .string("custom"),
        "customType": .string("advisor"),
        "display": .bool(true),
        "content": .string("Reviewer notes are ready."),
    ])

    #expect(reducer.consume(.event(type: "message_start", payload: .object(["message": shown]))) != .none)
    #expect(reducer.items.count == 1)
}

@Test func aDisplayedSkillMessageCompletesBeforeTheAssistantStarts() {
    var reducer = TranscriptReducer()
    let skillText = "# Skill\n\n" + String(
        repeating: "Follow this instruction carefully.\n",
        count: 240)
    let skill = JSONValue.object([
        "id": .string("skill-1"),
        "role": .string("custom"),
        "customType": .string("skill-prompt"),
        "display": .bool(true),
        "content": .string(skillText),
    ])
    let assistant = JSONValue.object([
        "id": .string("assistant-1"),
        "role": .string("assistant"),
        "content": .string("Starting work."),
    ])

    _ = reducer.consume(.event(
        type: "message_start",
        payload: .object(["message": skill])))
    _ = reducer.consume(.event(
        type: "message_start",
        payload: .object(["message": assistant])))

    let messages = reducer.items.compactMap { item -> TranscriptMessage? in
        guard case .message(let message) = item else { return nil }
        return message
    }
    #expect(messages.map(\.id) == ["skill-1", "assistant-1"])
    #expect(messages.first?.visibleText == skillText)
    #expect(messages.first?.isFinal == true)
}

@Test func aLateSkillSnapshotDoesNotReplaceTheStreamingAssistant() {
    var reducer = TranscriptReducer()
    let skillStart = JSONValue.object([
        "id": .string("skill-1"),
        "role": .string("custom"),
        "customType": .string("skill-prompt"),
        "display": .bool(true),
        "content": .string("# Skill\n\nInitial instructions."),
    ])
    let skillUpdate = JSONValue.object([
        "id": .string("skill-1"),
        "role": .string("custom"),
        "customType": .string("skill-prompt"),
        "display": .bool(true),
        "content": .string("# Skill\n\nComplete instructions."),
    ])
    let assistant = JSONValue.object([
        "id": .string("assistant-1"),
        "role": .string("assistant"),
        "content": .string("Starting work."),
    ])

    _ = reducer.consume(.event(
        type: "message_start",
        payload: .object(["message": skillStart])))
    _ = reducer.consume(.event(
        type: "message_start",
        payload: .object(["message": assistant])))
    _ = reducer.consume(.event(
        type: "message_update",
        payload: .object(["message": skillUpdate])))

    let messages = reducer.items.compactMap { item -> TranscriptMessage? in
        guard case .message(let message) = item else { return nil }
        return message
    }
    #expect(messages.map(\.id) == ["skill-1", "assistant-1"])
    #expect(messages[0].visibleText == "# Skill\n\nComplete instructions.")
    #expect(messages[0].isFinal == true)
    #expect(messages[1].visibleText == "Starting work.")
    #expect(messages[1].isFinal == false)
}

@Test func aChangeReplayedFromTheSessionFileIsNotShownTwice() {
    var reducer = TranscriptReducer()
    _ = reducer.consume(.event(
        type: "thinking_level_changed",
        payload: .object(["resolved": .string("high")])))
    #expect(reducer.items.count == 1)

    let persisted = TranscriptItem.annotation(TranscriptAnnotation(
        id: "entry-42",
        kind: .thinking,
        title: "Thinking set to High",
        detail: nil,
        timestamp: nil,
        tone: .neutral))
    _ = reducer.reconcile(history: TranscriptHistory(items: [persisted]))

    #expect(reducer.items.count == 1)
    #expect(reducer.items[0].id == "entry-42")
}

@Test func aLiveOnlyAnnotationSurvivesReconciliation() {
    var reducer = TranscriptReducer()
    _ = reducer.consume(.event(
        type: "auto_retry_start",
        payload: .object(["attempt": .int(2)])))
    #expect(reducer.items.count == 1)

    _ = reducer.reconcile(history: TranscriptHistory(items: []))

    // The session file has no entry for a retry, so dropping it would lose the
    // only record that the response was retried.
    #expect(reducer.items.count == 1)
}
