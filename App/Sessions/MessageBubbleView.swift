import OmpKit
import SwiftUI

struct MessageBubbleView: View {
    let message: TranscriptMessage

    static let assistantContentSpacing: CGFloat = 14
    static let assistantMaxWidth = TranscriptView.contentMaxWidth

    static func visibleText(from message: JSONValue) -> String {
        TranscriptMessage.visibleText(from: message)
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
            VStack(alignment: .trailing, spacing: 8) {
                ForEach(Array(message.document.images.enumerated()), id: \.offset) { _, image in
                    MessageImageView(image: image)
                }
                if !message.visibleText.isEmpty {
                    Text(message.visibleText)
                        .font(TenXTypography.body(size: 14))
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(TenXPalette.color(TenXPalette.nearBlackHex))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
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
            Text(message.visibleText)
                .font(TenXTypography.mono(size: 12))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
