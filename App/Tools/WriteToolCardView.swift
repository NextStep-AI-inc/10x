import SwiftUI

struct WriteToolCardView: View {
    let presentation: ToolPresentation

    var body: some View {
        if let content = ToolContentExtractor.file(presentation) {
            ToolCardScaffold(
                presentation: presentation,
                title: "Write",
                subtitle: content.path
            ) {
                Text(content.summary)
                    .font(TenXTypography.mono(size: 9))
                    .foregroundStyle(TenXPalette.color(TenXPalette.cyanHex))
                if !content.preview.isEmpty {
                    Text(content.preview)
                        .font(TenXTypography.mono(size: 10))
                        .lineLimit(8)
                        .textSelection(.enabled)
                }
            }
        } else {
            GenericToolCardView(presentation: presentation)
        }
    }
}
