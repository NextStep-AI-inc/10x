import SwiftUI

struct ReadToolCardView: View {
    let presentation: ToolPresentation

    var body: some View {
        if let content = ToolContentExtractor.file(presentation) {
            ToolCardScaffold(
                presentation: presentation,
                title: "Read",
                subtitle: content.path
            ) {
                HStack {
                    Text(content.summary)
                        .font(TenXTypography.mono(size: 9))
                        .foregroundStyle(TenXPalette.color(TenXPalette.cyanHex))
                    Spacer()
                }
                if !content.preview.isEmpty {
                    Text(content.preview)
                        .font(TenXTypography.mono(size: 10))
                        .lineLimit(10)
                        .textSelection(.enabled)
                }
            }
        } else {
            GenericToolCardView(presentation: presentation)
        }
    }
}
