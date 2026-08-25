import SwiftUI

struct WriteToolCardView: View {
    let presentation: ToolPresentation

    var body: some View {
        if let content = ToolContentExtractor.file(presentation) {
            ToolCardScaffold(
                presentation: presentation,
                title: "Write",
                fileReference: .file(path: content.path, line: nil)
            ) {
                Text(content.summary)
                    .font(TenXTypography.mono(size: 10))
                    .foregroundStyle(TenXPalette.color(TenXPalette.cyanHex))
                BoundedToolOutputView(
                    text: content.preview,
                    lineLimit: 8,
                    emptyText: presentation.phase == .complete ? "No output" : nil,
                    font: TenXTypography.mono(size: 10))
            }
        } else {
            GenericToolCardView(presentation: presentation)
        }
    }
}
