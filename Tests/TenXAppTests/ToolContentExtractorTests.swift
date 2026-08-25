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
