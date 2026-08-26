import Foundation
import Testing
@testable import TenXApp

@Test func messageParserBuildsSemanticDocumentBlocks() {
    let document = MessageContentParser.parse("""
    # Result

    A **readable** paragraph that wraps normally.

    - first item
      - nested item
    - [x] finished item

    | File | State |
    | --- | --- |
    | App.swift | changed |

    ---

    > Keep the interface quiet.

    ```swift
    let answer = 10
    ```
    """)

    #expect(document.blocks.map(\.kind) == [
        .heading,
        .paragraph,
        .list,
        .table,
        .divider,
        .quote,
        .source,
    ])
    #expect(document.plainText.contains("nested item"))
    #expect(document.plainText.contains("let answer = 10"))
}

@Test func unmatchedFenceStaysVisibleInsteadOfDroppingContent() {
    let document = MessageContentParser.parse("""
    Before

    ```text
    unfinished
    """)

    #expect(document.blocks.map(\.kind) == [.paragraph, .paragraph])
    #expect(document.plainText == "Before\n```text\nunfinished")
}

@Test func parserPreservesLongUnbrokenContent() {
    let longPath = "/tmp/" + String(repeating: "segment", count: 100) + ".swift"
    #expect(MessageContentParser.parse(longPath).plainText == longPath)
}

@Test func transcriptMessageNormalizesContentAtInitialization() {
    let message = TranscriptMessage(
        id: "message",
        raw: .object([
            "role": .string("assistant"),
            "content": .string("## Result\n\nRendered once."),
        ]),
        isFinal: true)

    #expect(message.document.blocks.map(\.kind) == [.heading, .paragraph])
    #expect(message.document.source == message.visibleText)
}

@Test func assistantTranscriptUsesReadableProseMetrics() {
    #expect(MessageBlockView.proseFontSize == 15)
    #expect(MessageBlockView.proseLineSpacing == 4)
    #expect(MessageBubbleView.assistantContentSpacing == 14)
    #expect(TranscriptView.contentMaxWidth == 860)
    #expect(MessageBubbleView.assistantMaxWidth == TranscriptView.contentMaxWidth)
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
