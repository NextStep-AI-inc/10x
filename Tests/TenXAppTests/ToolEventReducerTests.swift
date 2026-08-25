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

    reducer.consume(type: "tool_execution_end", payload: try payload("""
        {"type":"tool_execution_end","toolCallId":"t1","toolName":"bash","result":{"content":[{"type":"text","text":"/tmp/project"}]},"isError":false}
        """))

    #expect(reducer.presentations.count == 1)
    #expect(reducer.presentations[0].result?["content"]?.arrayValue?.first?["text"]?.stringValue == "/tmp/project")
    #expect(reducer.presentations[0].phase == .complete)
}

@Test func unknownToolsAlwaysUseTheGenericCard() {
    #expect(ToolCardRegistry.kind(for: "future_mcp_tool") == .generic)
}

@Test func priorityToolsResolveToTheirBespokeCards() {
    #expect(ToolCardRegistry.kind(for: "read") == .read)
    #expect(ToolCardRegistry.kind(for: "bash") == .bash)
    #expect(ToolCardRegistry.kind(for: "edit") == .edit)
    #expect(ToolCardRegistry.kind(for: "write") == .write)
    #expect(ToolCardRegistry.kind(for: "grep") == .search)
    #expect(ToolCardRegistry.kind(for: "glob") == .search)
    #expect(ToolCardRegistry.kind(for: "task") == .task)
    #expect(ToolCardRegistry.kind(for: "todo") == .todo)
    #expect(ToolCardRegistry.kind(for: "web_search") == .web)
    #expect(ToolCardRegistry.kind(for: "browser") == .web)
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
