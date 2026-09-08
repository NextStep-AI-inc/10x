import Testing
@testable import TenXApp

@Test func oneEchoConsumesOnlyOneRepeatedPendingSubmission() {
    let first = pending("Repeat this")
    let second = pending("Repeat this")
    var consumedIndices: Set<Int> = []

    let remaining = PendingUserSubmission.reconcile(
        [first, second],
        messages: [userMessage(id: "echo", text: "Repeat this")],
        consumedIndices: &consumedIndices)

    #expect(remaining == [second])
    #expect(consumedIndices == [0])
}

@Test func outOfOrderQueueEchoesConsumeTheirMatchingReceipts() {
    let first = pending("First queued prompt")
    let second = pending("Second queued prompt")
    let third = pending("Still waiting")
    var consumedIndices: Set<Int> = []

    let remaining = PendingUserSubmission.reconcile(
        [first, second, third],
        messages: [
            userMessage(id: "second-echo", text: "Second queued prompt"),
            userMessage(id: "first-echo", text: "First queued prompt"),
        ],
        consumedIndices: &consumedIndices)

    #expect(remaining == [third])
    #expect(consumedIndices == [0, 1])
}

@Test func historicalIdenticalEchoDoesNotConsumeANewerSubmission() {
    let newSubmission = PendingUserSubmission(
        text: "Repeat this",
        attachments: [],
        minimumUserIndex: 2,
        state: .sending)
    var consumedIndices: Set<Int> = []

    let remaining = PendingUserSubmission.reconcile(
        [newSubmission],
        messages: [
            userMessage(id: "historical-match", text: "Repeat this"),
            userMessage(id: "historical-other", text: "Different prompt"),
        ],
        consumedIndices: &consumedIndices)

    #expect(remaining == [newSubmission])
    #expect(consumedIndices.isEmpty)
}

private func pending(_ text: String) -> PendingUserSubmission {
    PendingUserSubmission(
        text: text,
        attachments: [],
        minimumUserIndex: 0,
        state: .queued(.followUp))
}

private func userMessage(id: String, text: String) -> TranscriptMessage {
    TranscriptMessage(
        id: id,
        raw: .object([
            "role": .string("user"),
            "content": .string(text),
        ]),
        isFinal: true)
}
