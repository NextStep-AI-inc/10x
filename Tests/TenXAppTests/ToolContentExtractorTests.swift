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
    #expect(fallback.primary == "future_tool")
    #expect(fallback.outcome == "Result")
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

@Test func consoleBodiesStripANSIControlsWithoutFlatteningLines() {
    let card = ToolContentExtractor.card(
        name: "bash",
        arguments: .object(["command": .string("swift test")]),
        result: result(text: "\u{001B}[31mFailed\u{001B}[0m\nNext line"),
        phase: .failed)

    guard case .stack(let bodies) = card.body,
          case .console(_, let output, _) = bodies.last
    else {
        Issue.record("Failed bash should retain a console after its error summary")
        return
    }
    #expect(output == "Failed\nNext line")
}

@Test func failedSingleLineConsoleDoesNotRepeatItsErrorAsOutput() {
    let card = ToolContentExtractor.card(
        name: "bash",
        arguments: .object(["command": .string("swift build")]),
        result: result(text: "Compilation failed"),
        phase: .failed)

    guard case .stack(let bodies) = card.body,
          bodies.count == 2,
          case .document(let error) = bodies[0],
          case .console(let command, let output, _) = bodies[1]
    else {
        Issue.record("A failed command should show one error followed by command context")
        return
    }
    #expect(error.plainText == "Compilation failed")
    #expect(command == "swift build")
    #expect(output.isEmpty)
}

@Test func readAndWriteCardsExposeSourceAndFileSummaries() {
    let read = ToolContentExtractor.card(
        name: "read",
        arguments: .object(["path": .string("Sources/App.swift")]),
        result: result(text: "let value = 1\nlet next = 2"),
        phase: .complete)
    #expect(read.primary == "Sources/App.swift")
    #expect(read.outcome == "2 lines")
    guard case .source(let readSource, let previewLines) = read.body else {
        Issue.record("Read should use the source surface")
        return
    }
    #expect(readSource.language == "swift")
    #expect(previewLines == 20)

    let write = ToolContentExtractor.card(
        name: "write",
        arguments: .object([
            "path": .string("Scripts/check.py"),
            "content": .string("def check():\n    return True"),
        ]),
        result: result(text: "Wrote Scripts/check.py"),
        phase: .complete)
    #expect(write.primary == "Scripts/check.py")
    #expect(write.outcome == "2 lines")
    guard case .source(let writtenSource, _) = write.body else {
        Issue.record("Write should show the created source")
        return
    }
    #expect(writtenSource.language == "py")
}

@Test func editAliasesPreserveMultiFileDiffsAndCounts() {
    let patch = """
    diff --git a/App/A.swift b/App/A.swift
    --- a/App/A.swift
    +++ b/App/A.swift
    @@ -1 +1 @@
    -let a = 1
    +let a = 2
    diff --git a/App/B.swift b/App/B.swift
    --- a/App/B.swift
    +++ b/App/B.swift
    @@ -1 +1 @@
    -let b = 1
    +let b = 2
    """
    for name in ["edit", "apply_patch"] {
        let card = ToolContentExtractor.card(
            name: name,
            arguments: .object([:]),
            result: .object(["details": .object(["diff": .string(patch)])]),
            phase: .complete)
        #expect(card.primary == "2 files")
        #expect(card.outcome == "+2 −2")
        guard case .diff(let diff, _) = card.body else {
            Issue.record("\(name) should use the diff surface")
            continue
        }
        #expect(diff.files.count == 2)
    }
}

@Test func searchStructuralAndLSPCardsUseReferencedCollections() {
    let grep = ToolContentExtractor.card(
        name: "grep",
        arguments: .object(["pattern": .string("Transcript")]),
        result: .object(["details": .object(["matches": .array([
            .object([
                "path": .string("App/Transcript.swift"),
                "line": .int(12),
                "text": .string("struct Transcript"),
            ]),
        ])])]),
        phase: .complete)
    guard case .collection(let grepItems) = grep.body else {
        Issue.record("Grep should use a referenced collection")
        return
    }
    #expect(grepItems.first?.reference == .file(path: "App/Transcript.swift", line: 12))
    #expect(grepItems.first?.detail == "struct Transcript")

    let glob = ToolContentExtractor.card(
        name: "glob",
        arguments: .object(["pattern": .string("**/*.swift")]),
        result: .object(["details": .object(["paths": .array([])])]),
        phase: .complete)
    #expect(glob.outcome == "No paths found")
    #expect(glob.body == .empty("No paths found"))

    let ast = ToolContentExtractor.card(
        name: "ast_grep",
        arguments: .object(["pattern": .string("struct $NAME")]),
        result: .object(["details": .object(["matches": .array([
            .object(["path": .string("App/A.swift"), "line": .int(1)]),
            .object(["path": .string("App/B.swift"), "line": .int(8)]),
        ])])]),
        phase: .complete)
    #expect(ast.outcome == "2 items")
    guard case .collection = ast.body else {
        Issue.record("AST grep should use a collection")
        return
    }

    let lsp = ToolContentExtractor.card(
        name: "lsp",
        arguments: .object([
            "operation": .string("references"),
            "path": .string("App/A.swift"),
        ]),
        result: .object(["details": .object(["results": .array([
            .object(["path": .string("App/B.swift"), "line": .int(14)]),
        ])])]),
        phase: .complete)
    #expect(lsp.primary == "references")
    guard case .collection(let lspItems) = lsp.body else {
        Issue.record("LSP should use a referenced collection")
        return
    }
    #expect(lspItems.first?.reference == .file(path: "App/B.swift", line: 14))
}

@Test func astEditUsesChangedFileCollectionWhenNoPatchIsAvailable() {
    let card = ToolContentExtractor.card(
        name: "ast_edit",
        arguments: .object(["pattern": .string("old($X)")]),
        result: .object(["details": .object(["changedFiles": .array([
            .object([
                "path": .string("App/A.swift"),
                "additions": .int(2),
                "removals": .int(1),
            ]),
            .object([
                "path": .string("App/B.swift"),
                "additions": .int(1),
                "removals": .int(1),
            ]),
        ])])]),
        phase: .complete)

    #expect(card.primary == "2 files")
    #expect(card.outcome == "+3 −2")
    guard case .collection(let files) = card.body else {
        Issue.record("AST edit should list changed files when it has no patch")
        return
    }
    #expect(files.count == 2)
}

@Test func bashKeepsCompleteStreamingConsoleOutput() {
    let output = (1...40).map { "step \($0)" }.joined(separator: "\n")
    let card = ToolContentExtractor.card(
        name: "bash",
        arguments: .object(["command": .string("swift test")]),
        result: result(text: output),
        phase: .running)

    #expect(card.outcome == "40 lines")
    guard case .console(let command, let normalizedOutput, let exitCode) = card.body else {
        Issue.record("Bash should use the console surface while streaming")
        return
    }
    #expect(command == "swift test")
    #expect(normalizedOutput == output)
    #expect(exitCode == nil)
}

@Test func evalKeepsSourceInputAndStructuredResult() {
    let card = ToolContentExtractor.card(
        name: "eval",
        arguments: .object([
            "language": .string("python"),
            "code": .string("sum([1, 2, 3])"),
        ]),
        result: .object(["details": .object([
            "value": .int(6),
            "type": .string("int"),
        ])]),
        phase: .complete)

    guard case .stack(let bodies) = card.body,
          bodies.count == 2,
          case .source(let source, _) = bodies[0],
          case .data(let label, let value) = bodies[1]
    else {
        Issue.record("Eval should preserve source input and structured output")
        return
    }
    #expect(source.language == "python")
    #expect(label == "Result")
    #expect(value["value"]?.intValue == 6)
}

@Test func webBrowserAndGitHubCardsChooseSemanticBodies() {
    let web = ToolContentExtractor.card(
        name: "web_search",
        arguments: .object(["query": .string("OMP")]),
        result: .object(["details": .object(["results": .array([
            .object([
                "title": .string("OMP reference"),
                "url": .string("https://example.com/omp"),
                "snippet": .string("Protocol docs"),
            ]),
        ])])]),
        phase: .complete)
    guard case .collection(let sources) = web.body else {
        Issue.record("Web search should use a linked collection")
        return
    }
    #expect(sources.first?.reference == .web(
        url: "https://example.com/omp",
        label: "OMP reference"))

    let browser = ToolContentExtractor.card(
        name: "browser",
        arguments: .object([
            "action": .string("open"),
            "url": .string("https://example.com/guide"),
        ]),
        result: .object([
            "content": .array([.object([
                "type": .string("text"),
                "text": .string("# Guide\n\nReadable page content."),
            ])]),
            "details": .object(["links": .array([
                .object([
                    "title": .string("API"),
                    "url": .string("https://example.com/api"),
                ]),
            ])]),
        ]),
        phase: .complete)
    guard case .stack(let browserBodies) = browser.body,
          case .document = browserBodies.first,
          case .collection = browserBodies.last
    else {
        Issue.record("Browser should show readable content followed by links")
        return
    }

    let github = ToolContentExtractor.card(
        name: "github",
        arguments: .object([
            "operation": .string("checks"),
            "repository": .string("openai/codex"),
        ]),
        result: .object(["details": .object(["checks": .array([
            .object([
                "name": .string("build"),
                "status": .string("success"),
                "url": .string("https://github.com/openai/codex/actions/1"),
            ]),
        ])])]),
        phase: .complete)
    #expect(github.primary == "openai/codex")
    guard case .collection(let checks) = github.body else {
        Issue.record("GitHub should use a linked object collection")
        return
    }
    #expect(checks.first?.state == "success")
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
