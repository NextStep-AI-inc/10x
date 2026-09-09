import OmpKit
import SwiftUI

struct MessageBubbleView: View, Equatable {
    let message: TranscriptMessage
    let mode: StreamingBehavior?
    let highlightedQuery: String?

    static let assistantContentSpacing: CGFloat = 14
    static let assistantMaxWidth = TranscriptView.contentMaxWidth

    static func visibleText(from message: JSONValue) -> String {
        TranscriptMessage.visibleText(from: message)
    }

    init(
        message: TranscriptMessage,
        mode: StreamingBehavior? = nil,
        highlightedQuery: String? = nil
    ) {
        self.message = message
        self.mode = mode
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
            && lhs.mode == rhs.mode
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
                if let mode {
                    knownModeContent(text: userText, mode: mode)
                } else {
                    standardUserContent(text: userText)
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

    @ViewBuilder
    private func standardUserContent(text: String) -> some View {
        ForEach(Array(message.document.images.enumerated()), id: \.offset) { _, image in
            MessageImageView(image: image)
        }
        if !text.isEmpty {
            TranscriptPlainTextView(
                text: text,
                font: TenXTypography.body(size: 14),
                color: TenXPalette.onEmphasis,
                highlightedQuery: highlightedQuery)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(TenXPalette.color(TenXPalette.nearBlackHex))
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
    }

    private func knownModeContent(text: String, mode: StreamingBehavior) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: mode.iconName)
                Text(mode.presentationLabel)
            }
            .font(TenXTypography.mono(size: 10, weight: .semibold))
            .foregroundStyle(TenXPalette.onEmphasis)

            ForEach(Array(message.document.images.enumerated()), id: \.offset) { _, image in
                MessageImageView(image: image)
            }
            if !text.isEmpty {
                TranscriptPlainTextView(
                    text: text,
                    font: TenXTypography.body(size: 14),
                    color: TenXPalette.onEmphasis,
                    highlightedQuery: highlightedQuery)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .background(TenXPalette.color(TenXPalette.nearBlackHex))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(alignment: .leading) {
            Capsule()
                .fill(mode.accentColor)
                .frame(width: 3)
                .padding(.vertical, 7)
                .padding(.leading, 4)
        }
    }
}

private extension StreamingBehavior {
    var presentationLabel: String {
        switch self {
        case .followUp: "Follow-up"
        case .steer: "Steer"
        }
    }

    var iconName: String {
        switch self {
        case .followUp: "arrow.triangle.branch"
        case .steer: "arrow.up.right"
        }
    }

    var accentColor: Color {
        switch self {
        case .followUp: TenXPalette.color(TenXPalette.cyanHex)
        case .steer: TenXPalette.color(TenXPalette.yellowHex)
        }
    }
}
