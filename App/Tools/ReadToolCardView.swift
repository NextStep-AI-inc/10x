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
                        .font(TenXTypography.mono(size: 10))
                        .foregroundStyle(TenXPalette.color(TenXPalette.cyanHex))
                    Spacer()
                }
                BoundedToolOutputView(
                    text: content.preview,
                    lineLimit: 10,
                    emptyText: presentation.phase == .complete ? "No output" : nil,
                    font: TenXTypography.mono(size: 10))
            }
        } else {
            GenericToolCardView(presentation: presentation)
        }
    }
}
