import OmpKit
import SwiftUI

struct MessageBubbleView: View {
    let message: TranscriptMessage

    static func visibleText(from message: JSONValue) -> String {
        TranscriptMessage.visibleText(from: message)
    }

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 80) }

            content
                .frame(maxWidth: message.role == .user ? 620 : 780, alignment: .leading)

            if message.role != .user { Spacer(minLength: 80) }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        if message.role == .user {
            Text(message.visibleText)
                .font(TenXTypography.body(size: 14))
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(TenXPalette.color(TenXPalette.nearBlackHex))
                .clipShape(RoundedRectangle(cornerRadius: 5))
        } else if message.role == .assistant {
            VStack(alignment: .leading, spacing: 10) {
                ResponseMetadataView(message: message)
                ForEach(Array(MessageContentParser.parse(message.visibleText).enumerated()), id: \.offset) { _, block in
                    MessageBlockView(block: block)
                }
                let references = TranscriptReference.extract(from: message.visibleText)
                if !references.isEmpty {
                    FlowLayout(spacing: 2) {
                        ForEach(references, id: \.self) { reference in
                            TranscriptReferenceView(reference: reference)
                        }
                    }
                }
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
