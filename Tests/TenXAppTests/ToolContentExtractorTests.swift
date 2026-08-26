import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Test func extractsPriorityToolFamiliesFromOpaquePayloads() {
    let read = presentation(
        name: "read",
        arguments: .object(["path": .string("/tmp/App.swift")]),
        result: result(text: "line one\nline two"))
    #expect(ToolContentExtractor.file(read)?.path == "/tmp/App.swift")
    #expect(ToolContentExtractor.file(read)?.preview == "line one\nline two")

    let bash = presentation(
        name: "bash",
        arguments: .object(["command": .string("swift test")]),
        result: result(text: "Build complete"))
    #expect(ToolContentExtractor.bash(bash)?.command == "swift test")
    #expect(ToolContentExtractor.bash(bash)?.output == "Build complete")

    let edit = presentation(
        name: "edit",
        arguments: .object(["path": .string("/tmp/App.swift")]),
        result: .object(["details": .object([
            "diff": .string("@@ -1 +1 @@\n-old\n+new"),
        ])]))
    #expect(ToolContentExtractor.edit(edit)?.additions == 1)
    #expect(ToolContentExtractor.edit(edit)?.removals == 1)
    #expect(ToolContentExtractor.edit(edit)?.unifiedDiff?.files.first?.path == "/tmp/App.swift")

    let search = presentation(
        name: "grep",
        arguments: .object(["pattern": .string("SessionController")]),
        result: result(text: "App/Session.swift:14\nTests/SessionTests.swift:8"))
    #expect(ToolContentExtractor.search(search)?.query == "SessionController")
    #expect(ToolContentExtractor.search(search)?.matches.count == 2)

    let task = presentation(
        name: "task",
        arguments: .object([
            "title": .string("Inspect sessions"),
            "role": .string("explorer"),
            "model": .string("gpt-5.6"),
        ]),
        result: .object(["details": .object([
            "status": .string("complete"),
            "progress": .string("Found the reducer"),
        ])]))
    #expect(ToolContentExtractor.task(task)?.title == "Inspect sessions")
    #expect(ToolContentExtractor.task(task)?.status == "complete")

    let todo = presentation(
        name: "todo",
        arguments: .object(["todos": .array([
            .object(["content": .string("Map shell"), "status": .string("completed")]),
            .object(["content": .string("Build search"), "status": .string("in_progress")]),
        ])]))
    #expect(ToolContentExtractor.todos(todo).map(\.isComplete) == [true, false])

    let web = presentation(
        name: "web_search",
        arguments: .object(["query": .string("OMP docs")]),
        result: .object(["details": .object(["results": .array([
            .object([
                "title": .string("OMP Reference"),
                "url": .string("https://example.com/omp"),
                "snippet": .string("Protocol reference"),
            ]),
        ])])]))
    #expect(ToolContentExtractor.web(web)?.queryOrURL == "OMP docs")
    #expect(ToolContentExtractor.web(web)?.results.first?.title == "OMP Reference")
}

@Test func malformedPriorityPayloadsFailClosed() {
    let malformed = presentation(name: "read", arguments: .null, result: .null)
    #expect(ToolContentExtractor.file(malformed) == nil)
    #expect(ToolContentExtractor.bash(malformed) == nil)
    #expect(ToolContentExtractor.edit(malformed) == nil)
    #expect(ToolContentExtractor.search(malformed) == nil)
    #expect(ToolContentExtractor.task(malformed) == nil)
    #expect(ToolContentExtractor.todos(malformed).isEmpty)
    #expect(ToolContentExtractor.web(malformed) == nil)
}

@Test func cursorEditPayloadUsesResultPathWhenArgumentsOmitIt() throws {
    let edit = presentation(
        name: "edit",
        arguments: .object([
            "i": .string("Changing before to after"),
            "input": .string("[.build/verification/ExistingProbe.swift#F72E]"),
        ]),
        result: .object(["details": .object([
            "diff": .string("-old\n+new"),
            "path": .string(".build/verification/ExistingProbe.swift"),
        ])]))

    let content = try #require(ToolContentExtractor.edit(edit))

    #expect(content.path == ".build/verification/ExistingProbe.swift")
}

@Test func searchAndWebExtractionRetainsEveryResultForDisclosure() throws {
    let searchLines = (1...24).map { "App/File\($0).swift:\($0)" }.joined(separator: "\n")
    let search = presentation(
        name: "grep",
        arguments: .object(["pattern": .string("Session")]),
        result: result(text: searchLines))
    #expect(ToolContentExtractor.search(search)?.matches.count == 24)

    let webResults = (1...12).map { index in
        JSONValue.object([
            "title": .string("Result \(index)"),
            "url": .string("https://example.com/results/\(index)"),
        ])
    }
    let web = presentation(
        name: "web_search",
        arguments: .object(["query": .string("OMP")]),
        result: .object(["details": .object(["results": .array(webResults)])]))
    #expect(ToolContentExtractor.web(web)?.results.count == 12)
}

@Test func toolResultEnvelopePreservesOrderedTypedBlocks() {
    let envelope = ToolResultEnvelope(result: .object([
        "content": .array([
            .object(["type": .string("text"), "text": .string("Found 2")]),
            .object([
                "type": .string("image"),
                "data": .string("AA=="),
                "mimeType": .string("image/png"),
            ]),
            .object([
                "type": .string("resource_link"),
                "name": .string("report"),
                "uri": .string("file:///tmp/report.txt"),
            ]),
        ]),
        "details": .object(["count": .int(2)]),
    ]))

    #expect(envelope.blocks.map(\.kind) == [.text, .image, .resource])
    #expect(envelope.details?["count"]?.intValue == 2)
}

@Test func toolResultEnvelopeSuppressesDuplicateTextAndCapturesErrors() {
    let envelope = ToolResultEnvelope(result: .object([
        "content": .array([
            .object(["type": .string("text"), "text": .string("Permission denied")]),
            .object(["type": .string("text"), "text": .string("Permission denied")]),
        ]),
        "error": .string("Permission denied"),
    ]))

    #expect(envelope.blocks == [.text("Permission denied")])
    #expect(envelope.error == "Permission denied")
}

@Test func toolCardContentUsesSemanticBodiesAcrossFamilies() {
    let read = ToolContentExtractor.card(
        name: "read",
        arguments: .object(["path": .string("App/Session.swift")]),
        result: result(text: "let count = 2"),
        phase: .complete)
    #expect(read.primary == "App/Session.swift")
    guard case .source(let source, _) = read.body else {
        Issue.record("Read should normalize to a source body")
        return
    }
    #expect(source.language == "swift")

    let bash = ToolContentExtractor.card(
        name: "bash",
        arguments: .object(["command": .string("swift test")]),
        result: .object([
            "content": .array([.object([
                "type": .string("text"),
                "text": .string("Build complete"),
            ])]),
            "details": .object(["exitCode": .int(0)]),
        ]),
        phase: .complete)
    guard case .console(let command, let output, let exitCode) = bash.body else {
        Issue.record("Bash should normalize to a console body")
        return
    }
    #expect(command == "swift test")
    #expect(output == "Build complete")
    #expect(exitCode == 0)

    let task = ToolContentExtractor.card(
        name: "task",
        arguments: .object(["title": .string("Inspect sessions")]),
        result: .object(["details": .object(["status": .string("complete")])]),
        phase: .complete)
    guard case .progress(let progress) = task.body else {
        Issue.record("Task should normalize to a progress body")
        return
    }
    #expect(progress.title == "Inspect sessions")
    #expect(progress.status == "complete")

    let recall = ToolContentExtractor.card(
        name: "recall",
        arguments: .object(["query": .string("transcript")]),
        result: .object(["details": .object(["memories": .array([])])]),
        phase: .complete)
    #expect(recall.outcome == "No memories found")
    #expect(recall.body == .empty("No memories found"))
}

@Test func privateAndFallbackToolBodiesNeverLoseTheirContract() {
    let privateActivity = ToolContentExtractor.card(
        name: "think",
        arguments: .object(["thought": .string("private input")]),
        result: result(text: "private output"),
        phase: .running)
    #expect(privateActivity.title == "Working")
    #expect(privateActivity.body == .privateActivity)

    let fallback = ToolContentExtractor.card(
        name: "future_tool",
        arguments: .object(["alpha": .int(1)]),
        result: .object(["unexpected": .array([.bool(true)])]),
        phase: .complete)
    #expect(fallback.title == "future_tool")
    guard case .stack(let bodies) = fallback.body else {
        Issue.record("Custom tools should retain arguments and results")
        return
    }
    #expect(bodies.count == 2)
}

@Test func failedToolContentPutsTheUsefulErrorFirst() {
    let card = ToolContentExtractor.card(
        name: "bash",
        arguments: .object(["command": .string("make")]),
        result: .object(["error": .string("Permission denied")]),
        phase: .failed)

    #expect(card.outcome == "Permission denied")
    guard case .stack(let bodies) = card.body,
          case .document(let error) = bodies.first
    else {
        Issue.record("Failed cards should put an error document first")
        return
    }
    #expect(error.plainText == "Permission denied")
}

private func presentation(
    name: String,
    arguments: JSONValue,
    result: JSONValue? = nil
) -> ToolPresentation {
    ToolPresentation(
        id: UUID().uuidString,
        name: name,
        arguments: arguments,
        result: result,
        phase: .complete,
        startDate: .distantPast,
        endDate: .distantPast)
}

private func result(text: String) -> JSONValue {
    .object(["content": .array([
        .object(["type": .string("text"), "text": .string(text)]),
    ])])
}
