import SwiftUI

struct TaskToolCardView: View {
    let presentation: ToolPresentation

    var body: some View {
        if let content = ToolContentExtractor.task(presentation) {
            ToolCardScaffold(
                presentation: presentation,
                title: "Task",
                subtitle: content.title
            ) {
                HStack(spacing: 10) {
                    if let role = content.role { metadata(role) }
                    if let model = content.model { metadata(model) }
                    metadata(content.status)
                }
                BoundedToolOutputView(
                    text: content.progress ?? "",
                    lineLimit: 5,
                    emptyText: presentation.phase == .complete ? "No output" : nil,
                    font: TenXTypography.body(size: 11))
            }
        } else {
            GenericToolCardView(presentation: presentation)
        }
    }

    private func metadata(_ value: String) -> some View {
        Text(value)
            .font(TenXTypography.mono(size: 10))
            .foregroundStyle(TenXPalette.color(TenXPalette.cyanHex))
    }
}
