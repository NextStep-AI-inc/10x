import Foundation
import OmpKit

struct PendingUserSubmission: Identifiable, Equatable, Sendable {
    enum State: Equatable, Sendable {
        case starting
        case sending
        case queued(StreamingBehavior)
        case unconfirmed

        var label: String {
            switch self {
            case .starting: "Starting session…"
            case .sending: "Sending…"
            case .queued(.steer): "Queued to steer"
            case .queued(.followUp): "Queued as follow-up"
            case .unconfirmed: "Delivery not confirmed. Review before retrying."
            }
        }
    }

    let id: String
    let message: TranscriptMessage
    let minimumUserIndex: Int
    var state: State

    init(text: String, attachments: [ComposerAttachment], minimumUserIndex: Int, state: State) {
        id = "pending-\(UUID().uuidString)"
        self.minimumUserIndex = minimumUserIndex
        self.state = state
        let images: [JSONValue] = attachments.map { attachment in
            .object(["type": .string("image"), "data": .string(attachment.data.base64EncodedString()),
                     "mimeType": .string(attachment.mimeType)])
        }
        message = TranscriptMessage(id: id, raw: .object([
            "role": .string("user"),
            "content": .array([.object(["type": .string("text"), "text": .string(text)])] + images),
        ]), timestamp: Date(), isFinal: true)
    }

    func matches(_ echo: TranscriptMessage) -> Bool {
        guard echo.role == .user, echo.document.images == message.document.images else { return false }
        if echo.visibleText == message.visibleText { return true }
        if let advisory = TranscriptMessage.advisoryContent(from: echo.raw) {
            return advisory.message == message.visibleText
        }
        // OMP can append structured advice to the user input before publishing
        // its echo. Only recognize that explicit suffix, not arbitrary prefixes.
        guard !message.visibleText.isEmpty, echo.visibleText.hasPrefix(message.visibleText) else { return false }
        let suffix = echo.visibleText.dropFirst(message.visibleText.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return suffix.hasPrefix("<advisory ")
    }

    static func reconcile(
        _ pending: [Self],
        messages: [TranscriptMessage],
        consumedIndices: inout Set<Int>
    ) -> [Self] {
        var remaining = pending
        for (index, message) in messages.enumerated() where !consumedIndices.contains(index) {
            guard let match = remaining.firstIndex(where: {
                index >= $0.minimumUserIndex && $0.matches(message)
            }) else { continue }
            consumedIndices.insert(index)
            remaining.remove(at: match)
        }
        let minimum = remaining.map(\.minimumUserIndex).min() ?? messages.count
        consumedIndices = consumedIndices.filter { $0 >= minimum }
        return remaining
    }
}
