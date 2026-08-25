import SwiftUI

struct MessageBlockView: View {
    let block: MessageBlock

    static let proseFontSize: CGFloat = 15
    static let proseLineSpacing: CGFloat = 4

    var body: some View {
        switch block {
        case .paragraph(let text):
            markdown(text)
                .font(TenXTypography.body(size: Self.proseFontSize))
        case .heading(let level, let text):
            markdown(text)
                .font(TenXTypography.body(
                    size: level == 1 ? 19 : max(Self.proseFontSize, 18 - CGFloat(level)),
                    weight: .semibold))
                .padding(.top, level == 1 ? 3 : 0)
        case .unorderedList(let items):
            list(items: items, ordered: false)
        case .orderedList(let items):
            list(items: items, ordered: true)
        case .quote(let text):
            markdown(text)
                .font(TenXTypography.body(size: Self.proseFontSize))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(TenXPalette.color(TenXPalette.nearBlackHex))
                        .frame(width: 2)
                }
        case .code(let language, let text):
            CodeBlockView(language: language, code: text)
        }
    }

    private func markdown(_ text: String) -> some View {
        Text((try? AttributedString(markdown: text)) ?? AttributedString(text))
            .lineSpacing(Self.proseLineSpacing)
            .textSelection(.enabled)
    }

    private func list(items: [String], ordered: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(ordered ? "\(index + 1)." : "•")
                        .font(TenXTypography.body(size: 13, weight: .semibold))
                        .frame(width: 20, alignment: .trailing)
                    markdown(item)
                        .font(TenXTypography.body(size: Self.proseFontSize))
                }
            }
        }
    }
}
