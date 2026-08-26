import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Test func toolUpdatesAndCompletionReplaceResultSnapshots() throws {
    var reducer = ToolEventReducer()

    reducer.consume(type: "tool_execution_start", payload: try payload("""
        {"type":"tool_execution_start","toolCallId":"t1","toolName":"bash","args":{"command":"pwd"}}
        """))
    reducer.consume(type: "tool_execution_update", payload: try payload("""
        {"type":"tool_execution_update","toolCallId":"t1","toolName":"bash","args":{"command":"pwd"},"partialResult":{"content":[{"type":"text","text":"/tmp"}]}}
        """))

    #expect(reducer.presentations.count == 1)
    #expect(reducer.presentations[0].result?["content"]?.arrayValue?.first?["text"]?.stringValue == "/tmp")
    #expect(reducer.presentations[0].phase == .running)
    guard case .console(_, let partialOutput, _) = reducer.presentations[0].content.body else {
        Issue.record("Running bash output should refresh its normalized console")
        return
    }
    #expect(partialOutput == "/tmp")

    reducer.consume(type: "tool_execution_end", payload: try payload("""
        {"type":"tool_execution_end","toolCallId":"t1","toolName":"bash","result":{"content":[{"type":"text","text":"/tmp/project"}]},"isError":false}
        """))

    #expect(reducer.presentations.count == 1)
    #expect(reducer.presentations[0].result?["content"]?.arrayValue?.first?["text"]?.stringValue == "/tmp/project")
    #expect(reducer.presentations[0].arguments["command"]?.stringValue == "pwd")
    #expect(reducer.presentations[0].phase == .complete)
    guard case .console(_, let finalOutput, _) = reducer.presentations[0].content.body else {
        Issue.record("Completed bash output should refresh its normalized console")
        return
    }
    #expect(finalOutput == "/tmp/project")
}

@Test func presentationRefreshesNormalizedContentAfterEverySemanticMutation() {
    var presentation = ToolPresentation(
        id: "tool",
        name: "read",
        arguments: .object(["path": .string("Old.swift")]),
        result: .string("old"),
        phase: .running,
        startDate: .distantPast,
        endDate: nil)

    #expect(presentation.content.primary == "Old.swift")
    presentation.name = "grep"
    presentation.arguments = .object(["pattern": .string("Session")])
    presentation.result = .object(["details": .object([
        "matches": .array([.string("App/Session.swift:12")]),
    ])])
    presentation.phase = .complete

    #expect(presentation.content.title == "Search")
    #expect(presentation.content.primary == "Session")
    #expect(presentation.content.outcome == "1 item")
}

@Test func unknownToolsAlwaysUseTheCustomCard() {
    #expect(ToolCardRegistry.kind(for: "future_mcp_tool") == .custom(name: "future_mcp_tool"))
}

@Test func priorityToolsResolveToTheirBespokeCards() {
    #expect(ToolCardRegistry.kind(for: "read") == .read)
    #expect(ToolCardRegistry.kind(for: "bash") == .bash)
    #expect(ToolCardRegistry.kind(for: "edit") == .edit)
    #expect(ToolCardRegistry.kind(for: "write") == .write)
    #expect(ToolCardRegistry.kind(for: "grep") == .grep)
    #expect(ToolCardRegistry.kind(for: "glob") == .glob)
    #expect(ToolCardRegistry.kind(for: "task") == .task)
    #expect(ToolCardRegistry.kind(for: "todo") == .todo)
    #expect(ToolCardRegistry.kind(for: "web_search") == .webSearch)
    #expect(ToolCardRegistry.kind(for: "browser") == .browser)
}

private func payload(_ json: String) throws -> JSONValue {
    guard case .event(_, let payload) = try RpcFrame.decode(line: Data(json.utf8)) else {
        throw TestPayloadError.notAnEvent
    }
    return payload
}

private enum TestPayloadError: Error {
    case notAnEvent
}
