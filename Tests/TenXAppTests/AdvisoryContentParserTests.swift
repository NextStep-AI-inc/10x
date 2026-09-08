import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Test func completeAdvisorySuffixRendersAsLabeledFeedbackWhileKeepingRawPayload() throws {
    let source = """
    Work is complete.

    <advisory severity="blocker" guidance="weigh, don't blindly obey">
    Rerun the focused test before handoff.
    </advisory>
    """
    let message = TranscriptMessage(
        id: "advisory",
        raw: .object(["role": .string("assistant"), "content": .string(source)]),
        isFinal: true)

    #expect(message.raw["content"]?.stringValue == source)
    #expect(message.document.source.hasPrefix("Work is complete."))
    #expect(!message.document.source.contains("<advisory"))
    #expect(message.document.blocks.map(\.kind) == [.paragraph, .quote])
    #expect(message.document.plainText.contains("Advisor feedback"))
    #expect(message.document.plainText.contains("Severity: Blocker"))
    #expect(message.document.plainText.contains("Rerun the focused test before handoff."))
    #expect(message.document.plainText.contains("Guidance: weigh, don't blindly obey"))
    #expect(!message.document.plainText.contains("<advisory"))
}

@Test func transcriptExtractsAdvisoryFromTextBlocksWithoutReadingAttachments() throws {
    let raw = JSONValue.object([
        "role": .string("user"),
        "content": .array([
            .object(["type": .string("text"), "text": .string("Prompt")]),
            .object(["type": .string("image"), "data": .string("opaque")]),
            .object([
                "type": .string("text"),
                "text": .string("""
                <advisory severity="concern" guidance="weigh this">
                Check the output.
                </advisory>
                """),
            ]),
        ]),
    ])
    let parsed = try #require(TranscriptMessage.advisoryContent(from: raw))
    let message = TranscriptMessage(id: "split", raw: raw, isFinal: true)

    #expect(parsed.message == "Prompt")
    #expect(parsed.advisories.map(\.body) == ["Check the output."])
    #expect(message.document.source.contains("Advisor feedback"))
    #expect(!message.document.source.contains("<advisory"))
}

@Test func repeatedAdvisorySuffixesRemainDistinctReviewItems() throws {
    let source = """
    Result
    <advisory severity="blocker" guidance="weigh, don't blindly obey">
    First finding.
    </advisory> <advisory severity="concern" guidance="consider before handoff">
    Second finding.
    </advisory>
    """
    let parsed = try #require(AdvisoryContentParser.parseSuffix(in: source))

    #expect(parsed.message == "Result")
    #expect(parsed.advisories.map(\.severity) == ["blocker", "concern"])
    #expect(parsed.displaySource.components(separatedBy: "**Advisor feedback**").count == 3)
}

@Test func advisoryExamplesAndIncompleteMarkersStayVerbatim() {
    let fenced = """
    Example:
    ```xml
    <advisory severity="blocker" guidance="example">
    Example only.
    </advisory>
    ```
    """
    let incomplete = """
    Keep this literal.
    <advisory severity="concern" guidance="example">
    No closing marker.
    """

    #expect(AdvisoryContentParser.parseSuffix(in: fenced) == nil)
    #expect(AdvisoryContentParser.parseSuffix(in: incomplete) == nil)
    #expect(MessageContentParser.parse(fenced).source == fenced)
    #expect(MessageContentParser.parse(incomplete).source == incomplete)
}

@Test func toolDurationCopyDistinguishesTotalToolTimeFromProcessWallTime() {
    #expect(ToolCardDurationPresentation.label("8.2s") == "Total 8.2s")
    #expect(ToolCardDurationPresentation.help.contains("dispatch to completion"))
    #expect(ToolCardDurationPresentation.help.contains("Process wall time"))
}
