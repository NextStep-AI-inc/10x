import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Test func transcriptSearchRequestRequiresStableEntryAndTrimmedQuery() {
    #expect(TranscriptSearchRequest(entryID: nil, query: "needle") == nil)
    #expect(TranscriptSearchRequest(entryID: "message", query: "  \n") == nil)

    let nonce = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let request = TranscriptSearchRequest(entryID: "message", query: "  needle  ", nonce: nonce)

    #expect(request?.entryID == "message")
    #expect(request?.query == "needle")
    #expect(request?.nonce == nonce)
}

@Test func transcriptSearchResolvesSplitMessageLineage() throws {
    let rows = TranscriptPresentationRow.rows(from: [
        .message(message(
            id: "assistant-entry",
            baseID: "assistant-entry",
            text: "Before the tool")),
        .tool(tool(id: "read-call")),
        .message(message(
            id: "assistant-entry-segment-1",
            baseID: "assistant-entry",
            text: "After the résumé tool")),
    ])
    let request = try #require(TranscriptSearchRequest(
        entryID: "assistant-entry",
        query: "RESUME"))

    let resolution = TranscriptSearchResolver.resolve(request, in: rows)

    #expect(resolution?.rowID == "message:assistant-entry-segment-1")
    #expect(resolution?.messageID == "assistant-entry-segment-1")
    #expect(resolution?.groupID == nil)
}

@Test func transcriptSearchResolvesGroupedTool() throws {
    let rows = TranscriptPresentationRow.rows(from: [
        .tool(tool(id: "read-call")),
        .tool(tool(id: "edit-call")),
    ])
    let request = try #require(TranscriptSearchRequest(
        entryID: "edit-call",
        query: "Cobalt.swift"))

    let resolution = TranscriptSearchResolver.resolve(request, in: rows)

    #expect(resolution?.rowID == "tool:edit-call")
    #expect(resolution?.groupID == "tool-group-read-call")
    #expect(resolution?.messageID == nil)
}

@Test func transcriptSearchDoesNotFallbackFromMissingTarget() throws {
    let rows = TranscriptPresentationRow.rows(from: [
        .message(message(id: "other", baseID: "other", text: "same needle")),
    ])
    let request = try #require(TranscriptSearchRequest(
        entryID: "deleted",
        query: "needle"))

    #expect(TranscriptSearchResolver.resolve(request, in: rows) == nil)
}

private func message(id: String, baseID: String, text: String) -> TranscriptMessage {
    TranscriptMessage(
        id: id,
        raw: .object([
            "role": .string("assistant"),
            "content": .string(text),
        ]),
        isFinal: true,
        renderLineageKey: .base(messageID: baseID))
}

private func tool(id: String) -> ToolPresentation {
    ToolPresentation(
        id: id,
        name: "read",
        arguments: .object(["path": .string("Cobalt.swift")]),
        result: nil,
        phase: .complete,
        startDate: .distantPast,
        endDate: .distantPast)
}
