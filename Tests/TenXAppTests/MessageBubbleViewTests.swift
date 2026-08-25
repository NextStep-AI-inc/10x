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
