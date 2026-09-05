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
    #expect(presentation.content.outcome == "1 match")
}

@Test func atomicPresentationUpdateNormalizesOneFinalState() {
    var presentation = ToolPresentation(
        id: "tool",
        name: "read",
        arguments: .object(["path": .string("Old.swift")]),
        result: .string("old"),
        phase: .running,
        startDate: .distantPast,
        endDate: nil)

    var normalizationCount = 0
    presentation.update(
        name: "grep",
        arguments: .object(["pattern": .string("Session")]),
        result: .some(.object(["details": .object([
            "matches": .array([.string("App/Session.swift:12")]),
        ])])),
        phase: .complete,
        endDate: .some(.distantFuture),
        normalizationObserver: { normalizationCount += 1 })

    #expect(normalizationCount == 1)
    #expect(presentation.content.title == "Search")
    #expect(presentation.content.primary == "Session")
    #expect(presentation.content.outcome == "1 match")
    #expect(presentation.endDate == .distantFuture)
}

@Test func identicalAtomicPresentationUpdateSkipsNormalizationAndKeepsContentIdentity() throws {
    let image = JSONValue.object([
        "content": .array([.object([
            "type": .string("image"),
            "data": .string("AQ=="),
            "mimeType": .string("image/png"),
            "name": .string("preview.png"),
        ])]),
    ])
    var presentation = ToolPresentation(
        id: "media",
        name: "inspect_image",
        arguments: .object([:]),
        result: image,
        phase: .complete,
        startDate: .distantPast,
        endDate: .distantFuture)
    let contentID = onlyMedia(in: presentation).contentID

    var normalizationCount = 0
    presentation.update(
        name: presentation.name,
        arguments: presentation.arguments,
        result: .some(presentation.result),
        phase: presentation.phase,
        endDate: .some(presentation.endDate),
        normalizationObserver: { normalizationCount += 1 })

    #expect(normalizationCount == 0)
    #expect(onlyMedia(in: presentation).contentID == contentID)
}

@Test func completedMediaResultKeepsItsGenerationWhenPayloadIsUnchanged() throws {
    var reducer = ToolEventReducer()
    let image = #"{"content":[{"type":"image","data":"AQ==","mimeType":"image/png","name":"preview.png"}]}"#

    reducer.consume(type: "tool_execution_update", payload: try payload("""
        {"type":"tool_execution_update","toolCallId":"media","toolName":"inspect_image","partialResult":\(image)}
        """))
    let runningGeneration = try #require(onlyMedia(in: reducer.presentations[0]).contentID)

    reducer.consume(type: "tool_execution_end", payload: try payload("""
        {"type":"tool_execution_end","toolCallId":"media","toolName":"inspect_image","result":\(image),"isError":false}
        """))

    #expect(onlyMedia(in: reducer.presentations[0]).contentID == runningGeneration)
}

@Test func changedMediaPayloadReplacesItsGenerationInTheSameSlot() throws {
    var reducer = ToolEventReducer()

    reducer.consume(type: "tool_execution_update", payload: try payload("""
        {"type":"tool_execution_update","toolCallId":"media","toolName":"inspect_image","partialResult":{"content":[{"type":"image","data":"AQ==","mimeType":"image/png","name":"preview.png"}]}}
        """))
    let runningGeneration = try #require(onlyMedia(in: reducer.presentations[0]).contentID)

    reducer.consume(type: "tool_execution_end", payload: try payload("""
        {"type":"tool_execution_end","toolCallId":"media","toolName":"inspect_image","result":{"content":[{"type":"image","data":"Ag==","mimeType":"image/png","name":"preview.png"}]},"isError":false}
        """))

    #expect(onlyMedia(in: reducer.presentations[0]).contentID != runningGeneration)
}

@Test func unchangedSourceRefreshKeepsItsRenderGeneration() throws {
    var presentation = ToolPresentation(
        id: "source",
        name: "read",
        arguments: .object(["path": .string("App.swift")]),
        result: .object(["content": .array([.object([
            "type": .string("text"),
            "text": .string("let value = 1"),
        ])])]),
        phase: .running,
        startDate: .distantPast,
        endDate: nil)
    let runningGeneration = try #require(onlySource(in: presentation)?.contentID)

    presentation.phase = .complete

    #expect(onlySource(in: presentation)?.contentID == runningGeneration)
}

@Test func unchangedDiffRefreshKeepsItsRenderGeneration() throws {
    let diff = "@@ -1 +1 @@\n-old\n+new"
    var presentation = ToolPresentation(
        id: "diff",
        name: "edit",
        arguments: .object(["path": .string("App.swift")]),
        result: .object(["details": .object(["diff": .string(diff)])]),
        phase: .running,
        startDate: .distantPast,
        endDate: nil)
    let runningGeneration = try #require(onlyDiff(in: presentation)?.renderID)

    presentation.phase = .complete

    #expect(onlyDiff(in: presentation)?.renderID == runningGeneration)
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

private func onlyMedia(in presentation: ToolPresentation) -> ToolMediaItem {
    guard case .media(let media, _) = presentation.content.body,
          let item = media.first else {
        Issue.record("Expected exactly one media item")
        return ToolMediaItem(
            id: "missing",
            kind: .other,
            name: nil,
            mimeType: nil,
            data: nil,
            url: nil)
    }
    return item
}

private func onlySource(in presentation: ToolPresentation) -> SourcePresentation? {
    guard case .source(let source, _) = presentation.content.body else { return nil }
    return source
}

private func onlyDiff(in presentation: ToolPresentation) -> UnifiedDiff? {
    guard case .diff(let diff, _) = presentation.content.body else { return nil }
    return diff
}

private enum TestPayloadError: Error {
    case notAnEvent
}
