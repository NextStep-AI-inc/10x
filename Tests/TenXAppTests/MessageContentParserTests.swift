import Foundation
import Testing
@testable import TenXApp

@Test func messageParserSeparatesSemanticMarkdownBlocks() {
    let blocks = MessageContentParser.parse("""
    # Result

    A readable paragraph that wraps normally.

    - first item
    - second item

    1. inspect
    2. change

    > Keep the interface quiet.

    ```swift
    let answer = 10
    ```
    """)

    #expect(blocks == [
        .heading(level: 1, text: "Result"),
        .paragraph("A readable paragraph that wraps normally."),
        .unorderedList(["first item", "second item"]),
        .orderedList(["inspect", "change"]),
        .quote("Keep the interface quiet."),
        .code(language: "swift", text: "let answer = 10"),
    ])
}

@Test func unmatchedFenceStaysVisibleInsteadOfDroppingContent() {
    let blocks = MessageContentParser.parse("""
    Before

    ```text
    unfinished
    """)

    #expect(blocks == [
        .paragraph("Before"),
        .paragraph("```text\nunfinished"),
    ])
}

@Test func parserPreservesLongUnbrokenContent() {
    let longPath = "/tmp/" + String(repeating: "segment", count: 100) + ".swift"
    #expect(MessageContentParser.parse(longPath) == [.paragraph(longPath)])
}

@Test func responseMetadataNamesActualModelModeAgentAndState() {
    let attribution = TranscriptResponseAttribution(
        provider: "openai-codex",
        model: "gpt-5.6-sol",
        mode: "plan",
        agent: "reviewer",
        modelRole: nil)

    #expect(ResponseMetadataView.labels(
        attribution: attribution,
        timestamp: nil,
        isFinal: false,
        stopReason: nil) == ["GPT-5.6 Sol", "Plan", "Reviewer", "Streaming"])
    #expect(ResponseMetadataView.labels(
        attribution: attribution,
        timestamp: nil,
        isFinal: true,
        stopReason: "error").suffix(1) == ["Error"])
}

@Test func responseMetadataAccessibilityNamesTheFullDate() {
    let label = ResponseMetadataView.accessibilityLabel(
        attribution: .none,
        timestamp: Date(timeIntervalSince1970: 1_787_601_600),
        isFinal: true,
        stopReason: nil)

    #expect(label.contains("2026"))
}
