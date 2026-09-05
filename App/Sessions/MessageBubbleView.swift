import OmpKit
import SwiftUI

struct MessageBubbleView: View, Equatable {
    let message: TranscriptMessage
    let highlightedQuery: String?

    static let assistantContentSpacing: CGFloat = 14
    static let assistantMaxWidth = TranscriptView.contentMaxWidth

    static func visibleText(from message: JSONValue) -> String {
        TranscriptMessage.visibleText(from: message)
    }

    init(message: TranscriptMessage, highlightedQuery: String? = nil) {
        self.message = message
        self.highlightedQuery = highlightedQuery
    }

    nonisolated static func == (lhs: MessageBubbleView, rhs: MessageBubbleView) -> Bool {
        lhs.message.id == rhs.message.id
            && lhs.message.role == rhs.message.role
            && lhs.message.document == rhs.message.document
            && lhs.message.timestamp == rhs.message.timestamp
            && lhs.message.attribution == rhs.message.attribution
            && lhs.message.isFinal == rhs.message.isFinal
            && lhs.message.showsResponseMetadata == rhs.message.showsResponseMetadata
            && lhs.message.stopReason == rhs.message.stopReason
            && lhs.highlightedQuery == rhs.highlightedQuery
    }

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 80) }

            content
                .frame(
                    maxWidth: message.role == .user ? 620 : Self.assistantMaxWidth,
                    alignment: message.role == .user ? .trailing : .leading)

        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        if message.role == .user {
            let advisory = TranscriptMessage.advisoryContent(from: message.raw)
            let userText = advisory?.message ?? message.visibleText
            VStack(alignment: .trailing, spacing: 8) {
                ForEach(Array(message.document.images.enumerated()), id: \.offset) { _, image in
                    MessageImageView(image: image)
                }
                if !userText.isEmpty {
                    TranscriptPlainTextView(
                        text: userText,
                        font: TenXTypography.body(size: 14),
                        color: TenXPalette.onEmphasis,
                        highlightedQuery: highlightedQuery)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(TenXPalette.color(TenXPalette.nearBlackHex))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                if let advisory {
                    let feedback = AdvisoryContentParser.Result(message: "", advisories: advisory.advisories)
                    ContentDocumentView(document: MessageContentParser.parse(feedback.displaySource))
                        .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else if message.role == .assistant {
            VStack(alignment: .leading, spacing: Self.assistantContentSpacing) {
                if message.showsResponseMetadata {
                    ResponseMetadataView(message: message)
                }
                AssistantMessageContentView(message: message)
                    .equatable()
            }
            .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
        } else {
            TranscriptPlainTextView(
                text: message.visibleText,
                font: TenXTypography.mono(size: 12),
                color: TenXPalette.color(TenXPalette.mutedTextHex))
        }
    }
}
