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
    guard case .message(let id, let message, let isFinal) = reducer.items[0] else {
        Issue.record("Expected one message item")
        return
    }
    #expect(id == "m1")
    #expect(message["content"]?.arrayValue?.first?["text"]?.stringValue == "Complete snapshot")
    #expect(!isFinal)
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
    guard case .message(_, let message, let isFinal) = reducer.items[0] else {
        Issue.record("Expected one message item")
        return
    }
    #expect(message["content"]?.arrayValue?.first?["text"]?.stringValue == "Final text")
    #expect(isFinal)
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

private func eventFrame(_ json: String) throws -> RpcFrame {
    try RpcFrame.decode(line: Data(json.utf8))
}
