import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Test func turnFilesUseStructuredMultiFileEditDiffs() {
    let section = turnSection([
        .tool(tool(
            id: "edit-1",
            name: "apply_patch",
            result: .object(["details": .object([
                "diff": .string("""
                diff --git a/App/Old.swift b/App/Feature.swift
                --- a/App/Old.swift
                +++ b/App/Feature.swift
                @@ -1 +1 @@
                -old
                +new
                diff --git a/Tests/OldTests.swift b/Tests/FeatureTests.swift
                --- a/Tests/OldTests.swift
                +++ b/Tests/FeatureTests.swift
                @@ -1 +1 @@
                -old
                +new
                """),
            ])]))),
    ])

    #expect(TranscriptTurnFiles.files(in: section) == [
        TranscriptTurnFile(path: "App/Feature.swift", toolID: "edit-1"),
        TranscriptTurnFile(path: "Tests/FeatureTests.swift", toolID: "edit-1"),
    ])
}

@Test func turnFilesUseWriteCardFileReference() {
    let section = turnSection([
        .tool(tool(
            id: "write-1",
            name: "write",
            arguments: .object([
                "path": .string(" App/NewFile.swift "),
                "content": .string("struct NewFile {}"),
            ]))),
    ])

    #expect(TranscriptTurnFiles.files(in: section) == [
        TranscriptTurnFile(path: "App/NewFile.swift", toolID: "write-1"),
    ])
}

@Test func turnFilesUseASTChangedFileCollectionsWhenNoDiffExists() {
    let section = turnSection([
        .tool(tool(
            id: "ast-1",
            name: "ast_edit",
            result: .object(["details": .object(["changedFiles": .array([
                .object(["path": .string("App/./One.swift")]),
                .object(["path": .string("App/Nested/../Two.swift")]),
            ])])]))),
    ])

    #expect(TranscriptTurnFiles.files(in: section) == [
        TranscriptTurnFile(path: "App/One.swift", toolID: "ast-1"),
        TranscriptTurnFile(path: "App/Two.swift", toolID: "ast-1"),
    ])
}

@Test func turnFilesPreserveFirstSeenOrderAndLinkDuplicatesToLatestTool() {
    let section = turnSection([
        .tool(tool(
            id: "edit-1",
            name: "edit",
            arguments: .object(["path": .string("App/One.swift")]),
            result: .object(["details": .object([
                "diff": .string("@@ -1 +1 @@\n-old\n+new"),
            ])]))),
        .tool(tool(
            id: "write-1",
            name: "write",
            arguments: .object([
                "path": .string("App/Two.swift"),
                "content": .string("two"),
            ]))),
        .tool(tool(
            id: "edit-2",
            name: "apply_patch",
            result: .object(["details": .object([
                "diff": .string("""
                diff --git a/App/One.swift b/App/./One.swift
                --- a/App/One.swift
                +++ b/App/./One.swift
                @@ -1 +1 @@
                -new
                +newer
                """),
            ])]))),
    ])

    #expect(TranscriptTurnFiles.files(in: section) == [
        TranscriptTurnFile(path: "App/One.swift", toolID: "edit-2"),
        TranscriptTurnFile(path: "App/Two.swift", toolID: "write-1"),
    ])
}

@Test func turnFilesIgnoreIncompleteUnregisteredShellAndEmptyPaths() {
    let section = turnSection([
        .tool(tool(
            id: "running-edit",
            name: "edit",
            phase: .running,
            arguments: .object(["path": .string("App/Running.swift")]))),
        .tool(tool(
            id: "failed-write",
            name: "write",
            phase: .failed,
            arguments: .object(["path": .string("App/Failed.swift")]))),
        .tool(tool(
            id: "shell-write",
            name: "bash",
            phase: .complete,
            arguments: .object(["command": .string("cat > App/Shell.swift")]))),
        .tool(tool(
            id: "empty-write",
            name: "write",
            phase: .complete,
            arguments: .object(["path": .string("   ")]))),
        .message(message(id: "assistant", text: "Edited App/Prose.swift")),
    ])

    #expect(TranscriptTurnFiles.files(in: section).isEmpty)
}

@Test func turnFilesKeepRelativeAndUnrelatedAbsolutePathsDistinct() {
    let section = turnSection([
        .tool(tool(
            id: "relative",
            name: "write",
            arguments: .object([
                "path": .string("App/File.swift"),
                "content": .string("relative"),
            ]))),
        .tool(tool(
            id: "absolute",
            name: "write",
            arguments: .object([
                "path": .string("/tmp/work/App/File.swift"),
                "content": .string("absolute"),
            ]))),
    ])

    #expect(TranscriptTurnFiles.files(in: section) == [
        TranscriptTurnFile(path: "App/File.swift", toolID: "relative"),
        TranscriptTurnFile(path: "/tmp/work/App/File.swift", toolID: "absolute"),
    ])
}

@Test func turnFilesExtractEachTranscriptTurnSectionSeparately() {
    let first = turnSection([
        .tool(tool(
            id: "first-write",
            name: "write",
            arguments: .object([
                "path": .string("App/First.swift"),
                "content": .string("first"),
            ]))),
    ])
    let second = turnSection([
        .tool(tool(
            id: "second-write",
            name: "write",
            arguments: .object([
                "path": .string("App/Second.swift"),
                "content": .string("second"),
            ]))),
    ])

    #expect(TranscriptTurnFiles.files(in: first) == [
        TranscriptTurnFile(path: "App/First.swift", toolID: "first-write"),
    ])
    #expect(TranscriptTurnFiles.files(in: second) == [
        TranscriptTurnFile(path: "App/Second.swift", toolID: "second-write"),
    ])
}

private func turnSection(_ items: [TranscriptItem]) -> TranscriptTurnSection {
    TranscriptTurnSection(id: UUID().uuidString, items: items, state: .completed, duration: nil)
}

private func tool(
    id: String,
    name: String,
    phase: ToolPhase = .complete,
    arguments: JSONValue = .object([:]),
    result: JSONValue? = nil
) -> ToolPresentation {
    ToolPresentation(
        id: id,
        name: name,
        arguments: arguments,
        result: result,
        phase: phase,
        startDate: Date(timeIntervalSince1970: 1),
        endDate: phase == .running ? nil : Date(timeIntervalSince1970: 2))
}

private func message(id: String, text: String) -> TranscriptMessage {
    TranscriptMessage(
        id: id,
        raw: .object([
            "role": .string("assistant"),
            "content": .string(text),
        ]),
        timestamp: Date(timeIntervalSince1970: 1),
        isFinal: true)
}
