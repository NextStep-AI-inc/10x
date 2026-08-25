import OmpKit
import SwiftUI

struct MessageBubbleView: View {
    let message: TranscriptMessage

    private var role: String {
        message.role.rawValue
    }

    private var text: String {
        message.visibleText
    }

    static func visibleText(from message: JSONValue) -> String {
        TranscriptMessage.visibleText(from: message)
    }

    var body: some View {
        HStack {
            if role == "user" { Spacer(minLength: 80) }

            content
                .frame(maxWidth: role == "user" ? 620 : 780, alignment: .leading)

            if role != "user" { Spacer(minLength: 80) }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        if role == "user" {
            Text(text)
                .font(TenXTypography.body(size: 14))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(TenXPalette.color(TenXPalette.nearBlackHex))
                .clipShape(RoundedRectangle(cornerRadius: 5))
        } else if role == "assistant" {
            Text(markdownText)
                .font(TenXTypography.body(size: 14))
                .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                .textSelection(.enabled)
        } else {
            Text(text)
                .font(TenXTypography.mono(size: 12))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                .textSelection(.enabled)
        }
    }

    private var markdownText: AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}
