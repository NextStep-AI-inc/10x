import OmpKit
import SwiftUI

struct MessageBubbleView: View {
    let message: JSONValue

    private var role: String {
        message["role"]?.stringValue ?? "unknown"
    }

    private var text: String {
        Self.visibleText(from: message)
    }

    static func visibleText(from message: JSONValue) -> String {
        if let content = message["content"]?.stringValue { return content }
        return message["content"]?.arrayValue?
            .compactMap { block in
                guard block["type"]?.stringValue == "text" else { return nil }
                return block["text"]?.stringValue
            }
            .joined(separator: "\n") ?? ""
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
