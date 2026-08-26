import Foundation
import OmpKit
import Testing
@testable import TenXApp

@MainActor @Test func visibleAssistantTextOmitsThinkingBlocks() {
    let message = JSONValue.object([
        "role": .string("assistant"),
        "content": .array([
            .object(["type": .string("thinking"), "thinking": .string("Internal reasoning")]),
            .object(["type": .string("text"), "text": .string("Visible answer")]),
        ]),
    ])

    #expect(MessageBubbleView.visibleText(from: message) == "Visible answer")
}

@MainActor @Test func assistantContentEqualityIgnoresUnrelatedTranscriptUpdates() {
    let original = assistantMessage(
        id: "assistant-1",
        text: "Stable answer",
        extraFields: ["internalRevision": .string("one")],
        isFinal: false)
    let unrelatedUpdate = assistantMessage(
        id: "assistant-1",
        text: "Stable answer",
        extraFields: ["internalRevision": .string("two")],
        isFinal: false)

    #expect(AssistantMessageContentView(message: original) == AssistantMessageContentView(message: unrelatedUpdate))
}

@MainActor @Test func assistantContentBoundaryExcludesResponseMetadata() {
    let message = assistantMessage(id: "assistant-1", text: "Stable answer", isFinal: false)
    let bodyDescription = String(describing: type(of: AssistantMessageContentView(message: message).body))

    #expect(!bodyDescription.contains("ResponseMetadataView"))
}

@MainActor @Test func assistantContentEqualityTracksIdentityTextAndFinality() {
    let base = assistantMessage(id: "assistant-1", text: "Stable answer", isFinal: false)

    #expect(AssistantMessageContentView(message: base) != AssistantMessageContentView(
        message: assistantMessage(id: "assistant-2", text: "Stable answer", isFinal: false)))
    #expect(AssistantMessageContentView(message: base) != AssistantMessageContentView(
        message: assistantMessage(id: "assistant-1", text: "Changed answer", isFinal: false)))
    #expect(AssistantMessageContentView(message: base) != AssistantMessageContentView(
        message: assistantMessage(id: "assistant-1", text: "Stable answer", isFinal: true)))
}

private func assistantMessage(
    id: String,
    text: String,
    timestamp: Date? = nil,
    attribution: TranscriptResponseAttribution = .none,
    extraFields: [String: JSONValue] = [:],
    isFinal: Bool
) -> TranscriptMessage {
    var raw: [String: JSONValue] = [
        "role": .string("assistant"),
        "content": .string(text),
    ]
    extraFields.forEach { raw[$0.key] = $0.value }
    return TranscriptMessage(
        id: id,
        raw: .object(raw),
        timestamp: timestamp,
        attribution: attribution,
        isFinal: isFinal)
}
